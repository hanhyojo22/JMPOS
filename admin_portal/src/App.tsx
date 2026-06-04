import { useEffect, useState } from "react";
import {
  Activity,
  CalendarClock,
  CheckCircle2,
  ChevronRight,
  CircleDollarSign,
  Copy,
  Download,
  KeyRound,
  Laptop,
  LogOut,
  Mail,
  Plus,
  RefreshCw,
  RotateCw,
  Search,
  Settings,
  ShieldAlert,
  Trash2,
  X,
} from "lucide-react";
import {
  adminApi,
  LicenseSummary,
  resetRedirectUrl,
  supabase,
  syncOwnerPasswordAfterRecovery,
} from "./api";

type Dashboard = {
  total: number;
  active: number;
  expiring: number;
  expired: number;
  suspended: number;
  activeDevices: number;
  recent: LicenseSummary[];
};
type LicenseDetail = {
  license: LicenseSummary & {
    ownerEmail: string;
    devices: Array<{ id: string; device_name: string | null; activated_at: string; last_seen_at: string; revoked_at: string | null }>;
  };
  audit: Array<{ id: string; action: string; created_at: string }>;
};

const emptyDashboard: Dashboard = { total: 0, active: 0, expiring: 0, expired: 0, suspended: 0, activeDevices: 0, recent: [] };
let resetSessionPreparation: Promise<boolean> | null = null;
let resetSessionPrepared = false;

export function App() {
  const isPasswordReset = globalThis.location.pathname === "/reset-password";
  const [sessionReady, setSessionReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  const [page, setPage] = useState<"dashboard" | "licenses" | "settings">("dashboard");
  const [dashboard, setDashboard] = useState(emptyDashboard);
  const [licenses, setLicenses] = useState<LicenseSummary[]>([]);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [selected, setSelected] = useState<LicenseDetail | null>(null);
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSignedIn(Boolean(data.session));
      setSessionReady(true);
    });
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => setSignedIn(Boolean(session)));
    return () => subscription.unsubscribe();
  }, []);
  useEffect(() => { if (signedIn) void refresh(); }, [signedIn]);
  useEffect(() => {
    if (!signedIn) return;
    const timer = globalThis.setTimeout(() => void refresh(), 300);
    return () => globalThis.clearTimeout(timer);
  }, [query, status]);

  async function refresh() {
    setBusy(true); setError("");
    try {
      const [metrics, list] = await Promise.all([
        adminApi<Dashboard>({ action: "dashboard" }),
        adminApi<{ licenses: LicenseSummary[] }>({ action: "list", search: query, status }),
      ]);
      setDashboard(metrics); setLicenses(list.licenses);
    } catch (e) { setError(message(e)); } finally { setBusy(false); }
  }
  async function openLicense(id: string) {
    setError("");
    try { setSelected(await adminApi<LicenseDetail>({ action: "details", inviteId: id })); }
    catch (e) { setError(message(e)); }
  }
  async function mutate(action: string, body: Record<string, unknown>) {
    setError("");
    try {
      const result = await adminApi<Record<string, unknown>>({ action, ...body });
      if (action === "remove-unused") setSelected(null);
      else if (selected) await openLicense(selected.license.id);
      await refresh();
      return result;
    } catch (e) { setError(message(e)); return null; }
  }
  if (isPasswordReset) return <ResetPassword />;
  if (!sessionReady) return <Loading />;
  if (!signedIn) return <Login />;

  if(busy && licenses.length==0 && dashboard.total===0){return <Loading/>;}
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand"><div className="brand-mark"><img src="/app-icon.png" alt=""/></div><div><strong>TindaPOS</strong><span>License Admin</span></div></div>
        <nav>
         
          <button type="button" className={page === "dashboard" ? "active" : ""} onClick={() => setPage("dashboard")}><Activity/>Dashboard</button>
          <button type="button" className={page === "licenses" ? "active" : ""} onClick={() => setPage("licenses")}><KeyRound/>Licenses</button>
          <button type="button" className={page === "settings" ? "active" : ""} onClick={() => setPage("settings")}><Settings/>Settings</button>
        </nav>
        <button type="button" className="signout" onClick={() => confirmSignOut() && void supabase.auth.signOut()}><LogOut/>Sign out</button>
      </aside>
      <main>
        <header><div><h1>{pageTitle(page)}</h1><p>{page === "settings" ? "Manage admin account access and sign-in details." : "Manage subscriptions, devices, and customer access."}</p></div>{page !== "settings" && <button type="button" className="primary" onClick={() => setCreating(true)}><Plus/>New license</button>}</header>
        {error && <div className="error"><ShieldAlert size={18}/>{error}</div>}
        {page === "dashboard" && <DashboardView data={dashboard} open={openLicense}/>}
        {page === "licenses" && <LicenseList licenses={licenses} query={query} setQuery={setQuery} status={status} setStatus={setStatus} refresh={refresh} busy={busy} open={openLicense}/>}
        {page === "settings" && <SettingsView/>}
      </main>
      {selected && <LicenseDrawer detail={selected} close={() => setSelected(null)} mutate={mutate}/>}
      {creating && <CreateModal close={() => setCreating(false)} created={() => { setCreating(false); void refresh(); }}/>}
    </div>
  );
}

function Login() {
  const [email, setEmail] = useState(""); const [password, setPassword] = useState(""); const [error, setError] = useState(""); const [busy, setBusy] = useState(false);
  async function submit(e: React.FormEvent) { e.preventDefault(); setBusy(true); setError(""); const { error } = await supabase.auth.signInWithPassword({ email, password }); if (error) setError(error.message); setBusy(false); }
  return <div className="login-page"><form className="login-panel" onSubmit={submit}><div className="brand-mark large"><img src="/app-icon.png" alt="TindaPOS"/></div><h1>TindaPOS License Admin</h1><p>Developer access only</p>{error && <div className="error">{error}</div>}<label>Email<input value={email} onChange={e => setEmail(e.target.value)} type="email" required/></label><label>Password<input value={password} onChange={e => setPassword(e.target.value)} type="password" required/></label><button type="submit" className="primary wide" disabled={busy}>{busy ? "Signing in..." : "Sign in"}</button></form></div>;
}

function ResetPassword() {
  const [ready,setReady]=useState(false);
  const [password,setPassword]=useState("");
  const [confirmPassword,setConfirmPassword]=useState("");
  const [resetEmail,setResetEmail]=useState("");
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [busy,setBusy]=useState(false);
  const [resetEmailBusy,setResetEmailBusy]=useState(false);
  const [resetEmailNotice,setResetEmailNotice]=useState("");
  async function readResetSessionFromUrl(){
    const url=new URL(globalThis.location.href);
    const params=url.searchParams;
    const hashParams=new URLSearchParams(url.hash.replace(/^#/,""));
    const accessToken=hashParams.get("access_token")||params.get("access_token");
    const refreshToken=hashParams.get("refresh_token")||params.get("refresh_token");
    const tokenHash=params.get("token_hash")||hashParams.get("token_hash");
    const code=params.get("code");
    if(accessToken&&refreshToken){
      const {error}=await supabase.auth.setSession({access_token:accessToken,refresh_token:refreshToken});
      if(error)throw error;
      globalThis.history.replaceState(null,"","/reset-password");
    }else if(tokenHash){
      const {error}=await supabase.auth.verifyOtp({token_hash:tokenHash,type:"recovery"});
      if(error)throw error;
      globalThis.history.replaceState(null,"","/reset-password");
    }else if(code){
      const {error}=await supabase.auth.exchangeCodeForSession(code);
      if(error)throw resetSessionError(error);
      globalThis.history.replaceState(null,"","/reset-password");
    }
    const {data}=await supabase.auth.getSession();
    resetSessionPrepared=Boolean(data.session);
    return resetSessionPrepared;
  }
  async function prepareResetSession(showError=false){
    try{
      if(resetSessionPrepared){
        setReady(true);
        return true;
      }
      resetSessionPreparation??=readResetSessionFromUrl().catch(e=>{
        resetSessionPreparation=null;
        throw e;
      });
      const hasSession=await resetSessionPreparation;
      setReady(hasSession);
      if(!hasSession&&showError)setError("Open the latest POS owner password reset link from your email. This reset session is missing or expired.");
      return hasSession;
    }catch(e){
      setReady(false);
      if(showError)setError(message(e));
      return false;
    }
  }
  useEffect(()=>{let mounted=true;async function prepare(){setError("");const url=new URL(globalThis.location.href);const hasResetToken=Boolean(url.searchParams.get("token_hash")||url.searchParams.get("code")||url.hash.includes("token_hash")||url.hash.includes("access_token"));const hasSession=await prepareResetSession(hasResetToken);if(!mounted)return;setReady(hasSession);}void prepare();const {data:{subscription}}=supabase.auth.onAuthStateChange((event,session)=>{if(!mounted)return;if(event==="PASSWORD_RECOVERY"||session){resetSessionPrepared=Boolean(session);setReady(Boolean(session));setError("");}});return()=>{mounted=false;subscription.unsubscribe();};},[]);
  async function sendResetEmail(){
    setError("");
    setResetEmailNotice("");
    const cleanEmail=resetEmail.trim().toLowerCase();
    if(!cleanEmail){setError("Enter the POS owner email first.");return;}
    if(!RegExp(/^[^@\s]+@[^@\s]+\.[^@\s]+$/).test(cleanEmail)){setError("Enter a valid POS owner email.");return;}
    setResetEmailBusy(true);
    try{
      const {error}=await supabase.auth.resetPasswordForEmail(cleanEmail,{redirectTo:resetRedirectUrl});
      if(error)throw error;
      setResetEmailNotice(`Password reset email sent to ${cleanEmail}. Open the newest link from this same browser.`);
    }catch(e){setError(message(e));}
    finally{setResetEmailBusy(false);}
  }
  async function submit(e:React.FormEvent){e.preventDefault();setError("");setNotice("");if(password.length<6){setError("Password must be at least 6 characters.");return;}if(password!==confirmPassword){setError("Passwords do not match.");return;}setBusy(true);try{const hasSession=ready||await prepareResetSession(true);if(!hasSession)return;const {error}=await supabase.auth.updateUser({password});if(error)throw error;const result=await syncOwnerPasswordAfterRecovery(password);if(result.updated===0)throw new Error("Password changed for this email, but no POS owner account was found. Use the owner email registered during POS license activation.");await supabase.auth.signOut();resetSessionPrepared=false;resetSessionPreparation=null;setReady(false);setNotice("POS owner password updated. The reset link is now closed. You can sign in to the POS app with the new password.");setPassword("");setConfirmPassword("");}catch(e){setError(message(e));}finally{setBusy(false);}}
  return <div className="login-page"><form className="login-panel" onSubmit={submit}><div className="brand-mark large"><img src="/app-icon.png" alt="TindaPOS"/></div><h1>Reset POS owner password</h1><p>Use the owner email registered during POS license activation.</p>{error && <div className="error">{error}</div>}{notice && <div className="notice">{notice}</div>}{resetEmailNotice && <div className="notice">{resetEmailNotice}</div>}<label>New password<input value={password} onChange={e=>setPassword(e.target.value)} type="password" minLength={6} required disabled={Boolean(notice)||busy}/></label><label>Confirm password<input value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} type="password" minLength={6} required disabled={Boolean(notice)||busy}/></label><button type="submit" className="primary wide" disabled={busy||Boolean(notice)}>{busy?"Updating...":"Update POS password"}</button><div className="reset-request"><label>Need a new reset email?<input value={resetEmail} onChange={e=>setResetEmail(e.target.value)} type="email" placeholder="POS owner email" disabled={resetEmailBusy}/></label><button type="button" className="secondary wide" disabled={resetEmailBusy} onClick={()=>void sendResetEmail()}>{resetEmailBusy?"Sending reset email...":"Send reset email"}</button></div><button type="button" className="text-button wide" onClick={()=>{globalThis.location.href="/";}}>Return to sign in</button></form></div>;
}
function DashboardView({ data, open }: { data: Dashboard; open: (id: string) => void }) {
  return <><section className="metrics"><Metric label="Active licenses" value={data.active} icon={<CheckCircle2/>}/><Metric label="Expiring soon" value={data.expiring} icon={<CalendarClock/>}/><Metric label="Expired" value={data.expired} icon={<ShieldAlert/>}/><Metric label="Active devices" value={data.activeDevices} icon={<Laptop/>}/></section><section className="panel"><div className="panel-title"><h2>Recent activity</h2><span>{data.total} total licenses</span></div><LicenseTable licenses={data.recent} open={open}/></section></>;
}
function Metric({ label, value, icon }: { label: string; value: number; icon: React.ReactNode }) { return <div className="metric"><div className="metric-icon">{icon}</div><span>{label}</span><strong>{value}</strong></div>; }
function SettingsView() {
  const [currentEmail,setCurrentEmail]=useState("");
  const [email,setEmail]=useState("");
  const [newPassword,setNewPassword]=useState("");
  const [confirmPassword,setConfirmPassword]=useState("");
  const [emailNotice,setEmailNotice]=useState("");
  const [passwordNotice,setPasswordNotice]=useState("");
  const [emailError,setEmailError]=useState("");
  const [passwordError,setPasswordError]=useState("");
  const [emailBusy,setEmailBusy]=useState(false);
  const [passwordBusy,setPasswordBusy]=useState(false);
  useEffect(()=>{let mounted=true;supabase.auth.getUser().then(({data,error})=>{if(!mounted)return;if(error){setEmailError(error.message);return;}const userEmail=data.user?.email??"";setCurrentEmail(userEmail);setEmail(userEmail);});return()=>{mounted=false};},[]);
  async function updateEmail(e:React.FormEvent){
    e.preventDefault();
    setEmailError("");setEmailNotice("");
    const cleanEmail=email.trim().toLowerCase();
    if(!cleanEmail){setEmailError("Enter an admin email address.");return;}
    if(cleanEmail===currentEmail.toLowerCase()){setEmailError("Enter a different email address.");return;}
    setEmailBusy(true);
    try{
      const {error}=await supabase.auth.updateUser({email:cleanEmail});
      if(error)throw error;
      setEmailNotice(`Confirmation email sent to ${cleanEmail}. Open the link in that inbox to finish changing the admin email.`);
    }catch(err){setEmailError(message(err));}
    finally{setEmailBusy(false);}
  }
  async function updatePassword(e:React.FormEvent){
    e.preventDefault();
    setPasswordError("");setPasswordNotice("");
    if(newPassword.length<6){setPasswordError("Password must be at least 6 characters.");return;}
    if(newPassword!==confirmPassword){setPasswordError("Passwords do not match.");return;}
    setPasswordBusy(true);
    try{
      const {error}=await supabase.auth.updateUser({password:newPassword});
      if(error)throw error;
      setNewPassword("");setConfirmPassword("");
      setPasswordNotice("Admin password updated. Use the new password the next time you sign in.");
    }catch(err){setPasswordError(message(err));}
    finally{setPasswordBusy(false);}
  }
  return <section className="settings-grid">
    <form className="panel settings-panel" onSubmit={updateEmail}>
      <div className="panel-title"><div><h2>Admin email</h2><span>Change the email used to sign in and receive password reset links.</span></div><Mail size={18}/></div>
      <div className="settings-form">{emailError&&<div className="error">{emailError}</div>}{emailNotice&&<div className="notice">{emailNotice}</div>}<label>Current email<input value={currentEmail||"Loading..."} disabled/></label><label>New email<input value={email} onChange={e=>setEmail(e.target.value)} type="email" required/></label><button type="submit" className="primary" disabled={emailBusy}>{emailBusy?"Sending confirmation...":"Update email"}</button></div>
    </form>
    <form className="panel settings-panel" onSubmit={updatePassword}>
      <div className="panel-title"><div><h2>Admin password</h2><span>Set a new password for this admin portal account.</span></div><KeyRound size={18}/></div>
      <div className="settings-form">{passwordError&&<div className="error">{passwordError}</div>}{passwordNotice&&<div className="notice">{passwordNotice}</div>}<label>New password<input value={newPassword} onChange={e=>setNewPassword(e.target.value)} type="password" minLength={6} required/></label><label>Confirm password<input value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} type="password" minLength={6} required/></label><button type="submit" className="primary" disabled={passwordBusy}>{passwordBusy?"Updating password...":"Update password"}</button></div>
    </form>
  </section>;
}
function LicenseList(p: { licenses: LicenseSummary[]; query: string; setQuery: (v: string) => void; status: string; setStatus: (v: string) => void; refresh: () => void; busy: boolean; open: (id: string) => void }) {
  return <section className="panel"><div className="toolbar"><div className="search"><Search size={17}/><input value={p.query} onChange={e=>p.setQuery(e.target.value)} placeholder="Search license, store, or account"/></div><select value={p.status} onChange={e=>p.setStatus(e.target.value)}><option value="">All statuses</option><option value="active">Active</option><option value="unused">Unused</option><option value="expired">Expired</option><option value="suspended">Suspended</option></select><button type="button" className="icon-button" title="Refresh" onClick={p.refresh}><RefreshCw size={17}/></button><button type="button" className="secondary" onClick={()=>exportCsv(p.licenses)}><Download/>CSV</button></div><LicenseTable licenses={p.licenses} open={p.open}/></section>;
}
function LicenseTable({ licenses, open }: { licenses: LicenseSummary[]; open: (id: string) => void }) { return <div className="table-wrap"><table><thead><tr><th>License</th><th>Account</th><th>Store</th><th>Status</th><th>Devices</th><th>Expires</th><th>Last activity</th><th/></tr></thead><tbody>{licenses.map(l=><tr key={l.id} onClick={()=>open(l.id)}><td><strong>{l.label}</strong></td><td>{l.ownerEmail||"Not activated"}</td><td>{l.storeName}</td><td><Badge state={l.state}/></td><td>{l.activeDeviceCount} / {l.slotLimit}</td><td><Expiry value={l.licenseExpiresAt}/></td><td>{date(l.lastActivityAt)}</td><td><ChevronRight size={16}/></td></tr>)}</tbody></table><div className="mobile-license-list">{licenses.map(l=><button type="button" className="mobile-license" key={l.id} onClick={()=>open(l.id)}><div className="mobile-license-head"><strong>{l.label}</strong><Badge state={l.state}/></div><span className="mobile-license-account">{l.ownerEmail||"Not activated"}</span><span>{l.storeName}</span><div className="mobile-license-meta"><span><Laptop size={14}/>{l.activeDeviceCount} / {l.slotLimit}</span><span><CalendarClock size={14}/><Expiry value={l.licenseExpiresAt}/></span><ChevronRight size={17}/></div></button>)}</div>{licenses.length===0&&<div className="empty">No licenses found.</div>}</div>; }
function Badge({ state }: { state: string }) { return <span className={`badge ${state}`}>{state}</span>; }
function LicenseDrawer({ detail, close, mutate }: { detail: LicenseDetail; close:()=>void; mutate:(a:string,b:Record<string,unknown>)=>Promise<Record<string,unknown>|null> }) {
  const l=detail.license;
  const isUnused=l.state==="unused";
  const [replacementCode,setReplacementCode]=useState("");
  const [recovery,setRecovery]=useState<{code:string;expiresAt:string;revokedDeviceName:string}|null>(null);
  const [copied,setCopied]=useState(false);
  const [renewalMonths,setRenewalMonths]=useState(12);
  const [testExpiry,setTestExpiry]=useState(toDateInput(l.licenseExpiresAt));
  const [testExpiryTime,setTestExpiryTime]=useState(toTimeInput(l.licenseExpiresAt));
  async function replaceCode(){if(!confirmUnusedCodeReplacement())return;const result=await mutate("replace-unused-code",{inviteId:l.id});if(typeof result?.code==="string"){setReplacementCode(result.code);setCopied(false)}}
  async function recoverLostPhone(device:{id:string;device_name:string|null}){if(!confirmLostPhoneRecovery(device.device_name))return;const result=await mutate("generate-recovery-code",{inviteId:l.id,deviceId:device.id});if(typeof result?.code==="string"&&typeof result.expiresAt==="string"){setRecovery({code:result.code,expiresAt:result.expiresAt,revokedDeviceName:typeof result.revokedDeviceName==="string"?result.revokedDeviceName:(device.device_name||"POS Device")});setCopied(false)}}
  async function copyCode(code:string){await navigator.clipboard.writeText(code);setCopied(true)}
  async function setExpiryDate(){if(!testExpiry||!testExpiryTime)return;await mutate("set-expiry-date",{inviteId:l.id,licenseExpiresAt:new Date(`${testExpiry}T${testExpiryTime}:00`).toISOString()})}
  return <div className="overlay"><aside className="drawer">
    <div className="drawer-head"><div><h2>{l.label}</h2><Badge state={l.state}/></div><button type="button" className="icon-button" aria-label="Close" onClick={close}><X/></button></div>
    <dl><dt>Store</dt><dd>{l.storeName}</dd><dt>Owner email</dt><dd>{l.ownerEmail||"Not activated"}</dd><dt>Expires</dt><dd><Expiry value={l.licenseExpiresAt}/></dd><dt>Devices</dt><dd>{l.activeDeviceCount} of {l.slotLimit} active</dd></dl>
    {isUnused&&<div className="unused-warning"><ShieldAlert/><div><strong>Unused license code</strong><span>This license has not been activated. For security, the original code cannot be viewed again. Replace it only when the customer needs a new code.</span></div></div>}
    {replacementCode&&<div className="generated"><span>New replacement license code</span><strong>{replacementCode}</strong><small>Copy this now. It is shown once only, and the previous code no longer works.</small><button type="button" className="secondary wide generated-copy" onClick={()=>void copyCode(replacementCode)}><Copy/>{copied?"Copied":"Copy code"}</button></div>}
    {recovery&&<div className="generated recovery-generated"><span>One-time lost-phone recovery code</span><strong>{recovery.code}</strong><small>Revoked device: {recovery.revokedDeviceName}</small><small>Expires: {dateTime(recovery.expiresAt)}</small><small>Give this code to the customer. Enter it in the replacement phone's normal license screen, then sign in with the original owner email and password.</small><button type="button" className="secondary wide generated-copy" onClick={()=>void copyCode(recovery.code)}><Copy/>{copied?"Copied":"Copy recovery code"}</button></div>}
    <div className="drawer-actions">{isUnused?<><button type="button" className="secondary" onClick={()=>{const n=prompt("Device slot limit",String(l.slotLimit));if(n)void mutate("set-slot-limit",{inviteId:l.id,slotLimit:Number(n)})}}><Laptop/>Change slots</button><button type="button" className="secondary" onClick={()=>void replaceCode()}><RotateCw/>Replace code</button><button type="button" className="danger" onClick={()=>confirmUnusedRemoval(l.label)&&void mutate("remove-unused",{inviteId:l.id})}><Trash2/>Remove</button></>:<><select value={renewalMonths} onChange={e=>setRenewalMonths(Number(e.target.value))} aria-label="Renewal duration"><option value={1}>1 month</option><option value={3}>3 months</option><option value={6}>6 months</option><option value={12}>1 year</option></select><button type="button" className="primary" onClick={()=>void mutate("renew",{inviteId:l.id,durationMonths:renewalMonths})}><CircleDollarSign/>Renew</button><button type="button" className="secondary" onClick={()=>{const n=prompt("Device slot limit",String(l.slotLimit));if(n)void mutate("set-slot-limit",{inviteId:l.id,slotLimit:Number(n)})}}><Laptop/>Change slots</button><button type="button" className="secondary" onClick={()=>void mutate(l.state==="suspended"?"reactivate":"suspend",{inviteId:l.id})}><ShieldAlert/>{l.state==="suspended"?"Reactivate":"Suspend"}</button></>}</div>
    <div className="testing-expiry"><div><strong>Testing expiry date and time</strong><span>Set an exact local date and minute to test expired and renewal flows.</span></div><div className="testing-expiry-controls"><input type="date" value={testExpiry} onChange={e=>setTestExpiry(e.target.value)}/><input type="time" value={testExpiryTime} onChange={e=>setTestExpiryTime(e.target.value)}/><button type="button" className="secondary" disabled={!testExpiry||!testExpiryTime} onClick={()=>void setExpiryDate()}><CalendarClock/>Set expiry</button></div></div>
    <h3>Devices</h3>{l.devices.length===0&&<div className="empty compact">No activated devices.</div>}{l.devices.map(d=><div className="device" key={d.id}><div><strong>{d.device_name||"POS Device"}</strong><span>{d.revoked_at?"Revoked":`Last seen ${date(d.last_seen_at)}`}</span></div>{!d.revoked_at&&<div className="device-actions"><button type="button" className="link-recovery" onClick={()=>void recoverLostPhone(d)}>Recover lost phone</button><button type="button" className="link-danger" onClick={()=>confirmDeviceRevoke(d.device_name)&&void mutate("revoke-device",{inviteId:l.id,deviceId:d.id})}>Revoke</button></div>}</div>)}
    <h3>Admin activity</h3>{detail.audit.map(a=><div className="audit" key={a.id}><span>{a.action}</span><time>{date(a.created_at)}</time></div>)}
  </aside></div>;
}
function CreateModal({ close, created }: { close:()=>void; created:()=>void }) {
  const [label,setLabel]=useState("");
  const [slots,setSlots]=useState(1);
  const [months,setMonths]=useState(12);
  const [code,setCode]=useState("");
  const [error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  const [copied,setCopied]=useState(false);
  async function submit(e:React.FormEvent){
    e.preventDefault();
    setBusy(true);setError("");
    try{const r=await adminApi<{code:string}>({action:"create",label:label.trim(),slotLimit:slots,durationMonths:months});setCode(r.code)}
    catch(e){setError(message(e))}
    finally{setBusy(false)}
  }
  async function copyCode(){await navigator.clipboard.writeText(code);setCopied(true)}
  return <div className="overlay center"><form className="modal license-modal" onSubmit={submit}><div className="drawer-head"><div><h2>New license</h2><p>Create a customer activation code.</p></div><button type="button" className="icon-button" aria-label="Close" onClick={close}><X/></button></div>{code?<><div className="generated"><span>Generated license code</span><strong>{code}</strong><small>Shown once only. Send this code to the customer securely.</small></div><div className="modal-actions"><button type="button" className="secondary" onClick={()=>void copyCode()}><Copy/>{copied?"Copied":"Copy code"}</button><button type="button" className="primary" onClick={created}>Done</button></div></>:<>{error&&<div className="error">{error}</div>}<div className="license-form"><label className="full">Customer or license label<input required autoFocus maxLength={80} placeholder="e.g. Maria's Grocery" value={label} onChange={e=>setLabel(e.target.value)}/></label><label>Subscription term<select value={months} onChange={e=>setMonths(Number(e.target.value))}><option value={1}>1 month</option><option value={3}>3 months</option><option value={6}>6 months</option><option value={12}>1 year</option></select></label><label>Device slots<input type="number" min={1} max={100} value={slots} onChange={e=>setSlots(Number(e.target.value))}/></label></div><div className="license-summary"><span>License validity</span><strong>{months===12?"1 year":`${months} month${months===1?"":"s"}`}</strong><small>{slots} active device slot{slots===1?"":"s"}</small></div><button type="submit" className="primary wide" disabled={busy}>{busy?"Generating...":"Generate license"}</button></>}</form></div>;
}
function Loading(){return <div className="loading">Loading...</div>}
function pageTitle(page:"dashboard"|"licenses"|"settings"){if(page==="dashboard")return"License overview";if(page==="licenses")return"Licenses";return"Settings"}
function date(v:string|null){return v?new Intl.DateTimeFormat(undefined,{dateStyle:"medium"}).format(new Date(v)):"-"}
function dateTime(v:string|null){return v?new Intl.DateTimeFormat(undefined,{dateStyle:"medium",timeStyle:"short"}).format(new Date(v)):"-"}
function Expiry({ value }: { value: string|null }) {
  const [now,setNow]=useState(Date.now());
  useEffect(()=>{
    if(!value)return;
    const expiry=new Date(value).getTime();
    const remaining=expiry-Date.now();
    if(!Number.isFinite(expiry)||remaining<=0)return;
    const delay=remaining>86_400_000?remaining-86_400_000:1_000;
    const timer=globalThis.setTimeout(()=>setNow(Date.now()),delay);
    return()=>globalThis.clearTimeout(timer);
  },[value,now]);
  if(!value)return <>-</>;
  const remaining=new Date(value).getTime()-now;
  if(remaining<=0||remaining>86_400_000)return <>{date(value)}</>;
  const totalSeconds=Math.floor(remaining/1_000);
  const hours=Math.floor(totalSeconds/3_600).toString().padStart(2,"0");
  const minutes=Math.floor(totalSeconds%3_600/60).toString().padStart(2,"0");
  const seconds=(totalSeconds%60).toString().padStart(2,"0");
  return <>{hours}:{minutes}:{seconds}</>;
}
function toDateInput(v:string|null){return v?new Date(v).toISOString().slice(0,10):""}
function toTimeInput(v:string|null){if(!v)return"23:59";const d=new Date(v);return Number.isFinite(d.getTime())?`${d.getHours().toString().padStart(2,"0")}:${d.getMinutes().toString().padStart(2,"0")}`:"23:59"}
function message(e: unknown) {
  if (e instanceof Error) return e.message;
  if (typeof e === "string") return e;

  try {
    return JSON.stringify(e);
  } catch {
    return "Something went wrong";
  }
}
function resetSessionError(e: unknown) {
  const text = message(e);
  if (text.toLowerCase().includes("auth code") && text.toLowerCase().includes("code verifier")) {
    return new Error("This reset email used the old link format. Update the Supabase recovery email template, then request a new POS owner password reset email and open the newest link.");
  }
  return e instanceof Error ? e : new Error(text);
}
function confirmDeviceRevoke(deviceName:string|null){return globalThis.confirm(`Revoke ${deviceName||"this POS device"}?\n\nThe customer's account and store data will remain safe. This device slot will be released. The phone can be activated again later with owner verification unless the license is suspended.`)}
function confirmLostPhoneRecovery(deviceName:string|null){return globalThis.confirm(`Recover a lost phone for ${deviceName||"this POS device"}?\n\nThis revokes the selected device immediately and creates a one-time recovery code valid for 24 hours. The replacement phone must still sign in with the original owner email and password.`)}
function confirmUnusedCodeReplacement(){return globalThis.confirm("Replace this unused license code?\n\nThe previous code will stop working immediately. This is allowed only before the license has been activated.")}
function confirmUnusedRemoval(label:string){return globalThis.confirm(`Remove unused license \"${label}\"?\n\nThis permanently deletes the license. This action is allowed only before activation and cannot be undone.`)}
function confirmSignOut(){return globalThis.confirm("Sign out of the license admin portal?")}
function exportCsv(rows:LicenseSummary[]){const cells=[["License","Account","Store","Status","Expiry","Active devices","Slots","Last activity"],...rows.map(r=>[r.label,r.ownerEmail||"Not activated",r.storeName,r.state,r.licenseExpiresAt??"",String(r.activeDeviceCount),String(r.slotLimit),r.lastActivityAt??""])];const csv=cells.map(row=>row.map(v=>`"${v.replaceAll('"','""')}"`).join(",")).join("\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv"}));a.download="tindapos-licenses.csv";a.click();URL.revokeObjectURL(a.href)}
