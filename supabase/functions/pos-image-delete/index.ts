import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const cloudImagePrefix = "supabase-storage://";
const productImagePrefix = "sync_images/products";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ImageDeleteBody = {
  operation?: "delete_product_image" | "cleanup_unused_images";
  storeId?: string;
  localId?: string;
  bucket?: string;
  imagePath?: string | null;
  syncEventId?: string | null;
};

type AdminClient = SupabaseClient;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as ImageDeleteBody;
    const operation = body.operation;
    const storeId = sanitizeUuid(body.storeId);
    const bucket = sanitizeBucket(body.bucket) || "backupfiles";

    if (!operation) return jsonResponse({ error: "Operation is required" }, 400);
    if (!storeId) return jsonResponse({ error: "Valid store id is required" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Image delete service is not configured" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const userId = await authenticatedUserId(admin, req);
    await assertStoreMember(admin, storeId, userId);

    if (operation === "delete_product_image") {
      const localId = sanitizeLocalId(body.localId);
      if (!localId) return jsonResponse({ error: "Valid local id is required" }, 400);
      const result = await deleteProductImage({
        admin,
        storeId,
        localId,
        bucket,
        imagePath: body.imagePath,
        syncEventId: sanitizeText(body.syncEventId, 200),
        userId,
      });
      return jsonResponse(result);
    }

    if (operation === "cleanup_unused_images") {
      const result = await cleanupUnusedImages({ admin, storeId, bucket, userId });
      return jsonResponse(result);
    }

    return jsonResponse({ error: "Unsupported operation" }, 400);
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      error instanceof AuthError ? error.status : 500,
    );
  }
});

async function deleteProductImage(args: {
  admin: AdminClient;
  storeId: string;
  localId: string;
  bucket: string;
  imagePath?: string | null;
  syncEventId: string;
  userId: string;
}) {
  const objectPath = objectPathForProductImage(
    args.storeId,
    args.localId,
    args.bucket,
    args.imagePath,
  );
  if (!objectPath) return { deleted: 0, status: "no_image" };

  await markProductPendingDelete(args.admin, args.storeId, args.localId);
  await upsertDeletion(args.admin, {
    storeId: args.storeId,
    localId: args.localId,
    bucket: args.bucket,
    objectPath,
    imageReference: args.imagePath ?? null,
    syncEventId: args.syncEventId,
    reason: "product_delete",
    status: "pending",
    userId: args.userId,
  });

  const { error: removeError } = await args.admin.storage
    .from(args.bucket)
    .remove([objectPath]);

  if (removeError) {
    await setDeletionStatus(args.admin, args.storeId, args.bucket, objectPath, {
      status: "failed",
      last_error: removeError.message,
    });
    throw removeError;
  }

  await setDeletionStatus(args.admin, args.storeId, args.bucket, objectPath, {
    status: "completed",
    completed_at: new Date().toISOString(),
    last_error: null,
  });
  return { deleted: 1, objectPath };
}

async function cleanupUnusedImages(args: {
  admin: AdminClient;
  storeId: string;
  bucket: string;
  userId: string;
}) {
  const folder = `${args.storeId}/${productImagePrefix}`;
  const { data: objects, error: listError } = await args.admin.storage
    .from(args.bucket)
    .list(folder, { limit: 1000 });
  if (listError) throw listError;

  const referenced = await referencedProductImagePaths(
    args.admin,
    args.storeId,
    args.bucket,
  );
  const stalePaths = ((objects ?? []) as Array<{ name: string }>)
    .map((object: { name: string }) => object.name)
    .filter((name: string) => name && isSupportedImageName(name))
    .map((name: string) => `${folder}/${name}`)
    .filter((path: string) => !referenced.has(path));

  if (stalePaths.length === 0) return { deleted: 0 };

  for (const path of stalePaths) {
    await upsertDeletion(args.admin, {
      storeId: args.storeId,
      localId: path.split("/").pop()?.split(".")[0] ?? "unknown",
      bucket: args.bucket,
      objectPath: path,
      imageReference: `${cloudImagePrefix}${args.bucket}/${path}`,
      syncEventId: "",
      reason: "cleanup_unused",
      status: "pending",
      userId: args.userId,
    });
  }

  const { error: removeError } = await args.admin.storage
    .from(args.bucket)
    .remove(stalePaths);
  if (removeError) throw removeError;

  for (const path of stalePaths) {
    await setDeletionStatus(args.admin, args.storeId, args.bucket, path, {
      status: "completed",
      completed_at: new Date().toISOString(),
      last_error: null,
    });
  }

  return { deleted: stalePaths.length };
}

async function referencedProductImagePaths(
  admin: AdminClient,
  storeId: string,
  bucket: string,
) {
  const { data, error } = await admin
    .from("products")
    .select("image_url, payload, pending_delete")
    .eq("store_id", storeId)
    .eq("pending_delete", false);
  if (error) throw error;

  const paths = new Set<string>();
  for (const row of data ?? []) {
    const imageUrl = imageReferenceFromRow(row);
    const parsed = parseStorageReference(imageUrl);
    if (parsed && parsed.bucket === bucket && belongsToStore(storeId, parsed.objectPath)) {
      paths.add(parsed.objectPath);
    }
  }
  return paths;
}

function imageReferenceFromRow(row: Record<string, unknown>) {
  const imageUrl = sanitizeText(row.image_url, 2000);
  if (imageUrl) return imageUrl;
  const payload = row.payload;
  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    return sanitizeText((payload as Record<string, unknown>).image_url, 2000);
  }
  return "";
}

async function markProductPendingDelete(
  admin: AdminClient,
  storeId: string,
  localId: string,
) {
  const { error } = await admin
    .from("products")
    .update({
      pending_delete: true,
      pending_delete_at: new Date().toISOString(),
      cloud_updated_at: new Date().toISOString(),
    })
    .eq("store_id", storeId)
    .eq("local_id", localId);
  if (error) throw error;
}

async function upsertDeletion(
  admin: AdminClient,
  row: {
    storeId: string;
    localId: string;
    bucket: string;
    objectPath: string;
    imageReference: string | null;
    syncEventId: string;
    reason: string;
    status: "pending" | "completed" | "failed";
    userId: string;
  },
) {
  const { error } = await admin.from("product_image_deletions").upsert(
    {
      store_id: row.storeId,
      local_product_id: row.localId,
      bucket_id: row.bucket,
      object_path: row.objectPath,
      image_reference: row.imageReference,
      sync_event_id: row.syncEventId || null,
      reason: row.reason,
      status: row.status,
      requested_by: row.userId,
      requested_at: new Date().toISOString(),
      last_error: null,
    },
    { onConflict: "store_id,bucket_id,object_path" },
  );
  if (error) throw error;
}

async function setDeletionStatus(
  admin: AdminClient,
  storeId: string,
  bucket: string,
  objectPath: string,
  values: Record<string, unknown>,
) {
  const { error } = await admin
    .from("product_image_deletions")
    .update(values)
    .eq("store_id", storeId)
    .eq("bucket_id", bucket)
    .eq("object_path", objectPath);
  if (error) throw error;
}

function objectPathForProductImage(
  storeId: string,
  localId: string,
  bucket: string,
  imagePath?: string | null,
) {
  const parsed = parseStorageReference(imagePath);
  if (parsed) {
    if (parsed.bucket !== bucket) throw new Error("Image bucket does not match");
    if (!belongsToStore(storeId, parsed.objectPath)) {
      throw new Error("Image path does not belong to this store");
    }
    return parsed.objectPath;
  }

  const path = sanitizeText(imagePath, 2000);
  if (!path || path.startsWith("http")) return "";
  const extension = imageExtension(path);
  return `${storeId}/${productImagePrefix}/${localId}${extension}`;
}

function parseStorageReference(value: unknown) {
  const text = sanitizeText(value, 2000);
  if (!text.startsWith(cloudImagePrefix)) return null;
  const reference = text.slice(cloudImagePrefix.length);
  const separator = reference.indexOf("/");
  if (separator <= 0 || separator === reference.length - 1) return null;
  return {
    bucket: reference.slice(0, separator),
    objectPath: reference.slice(separator + 1),
  };
}

function belongsToStore(storeId: string, objectPath: string) {
  return objectPath.startsWith(`${storeId}/${productImagePrefix}/`);
}

async function authenticatedUserId(
  admin: AdminClient,
  req: Request,
) {
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new AuthError("Missing authorization token", 401);

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new AuthError("Invalid authorization token", 401);
  return data.user.id;
}

async function assertStoreMember(
  admin: AdminClient,
  storeId: string,
  userId: string,
) {
  const { data, error } = await admin
    .from("store_members")
    .select("store_id")
    .eq("store_id", storeId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new AuthError("Store access denied", 403);
}

function sanitizeUuid(value: unknown) {
  const text = sanitizeText(value, 80);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(text)
    ? text
    : "";
}

function sanitizeBucket(value: unknown) {
  const text = sanitizeText(value, 120);
  return /^[a-zA-Z0-9._-]+$/.test(text) ? text : "";
}

function sanitizeLocalId(value: unknown) {
  const text = sanitizeText(value, 80);
  return /^[a-zA-Z0-9._:-]+$/.test(text) ? text : "";
}

function sanitizeText(value: unknown, maxLength: number) {
  const text = String(value ?? "").trim();
  return text.length <= maxLength ? text : "";
}

function imageExtension(path: string) {
  const match = path.toLowerCase().match(/\.(png|jpe?g|webp|gif)$/);
  return match ? match[0].replace(".jpeg", ".jpg") : ".jpg";
}

function isSupportedImageName(name: string) {
  return /\.(png|jpe?g|webp|gif)$/i.test(name);
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

class AuthError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
