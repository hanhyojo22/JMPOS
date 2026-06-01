param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\.env')
)

$ErrorActionPreference = 'Stop'

function Read-EnvFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Environment file was not found: $Path"
    }

    $values = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        $separator = $line.IndexOf('=')
        if ($separator -le 0) {
            continue
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
        if ($key) {
            $values[$key] = $value
        }
    }

    return $values
}

function Get-ErrorResponseBody {
    param($ErrorRecord)

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return $ErrorRecord.ErrorDetails.Message
    }

    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.GetResponseStream) {
        $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }

    return ''
}

function Assert-PublicFunctionConfig {
    $configPath = Join-Path $PSScriptRoot '..\supabase\config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Supabase config was not found: $configPath"
    }

    $config = Get-Content -LiteralPath $configPath -Raw
    foreach ($functionName in @('validate-license', 'register-store-v2')) {
        $escapedName = [regex]::Escape($functionName)
        $pattern = "(?ms)^\[functions\.$escapedName\]\s*^verify_jwt\s*=\s*false\s*$"
        if ($config -notmatch $pattern) {
            throw "supabase/config.toml must contain [functions.$functionName] with verify_jwt = false."
        }
    }
}

Assert-PublicFunctionConfig

$envValues = Read-EnvFile -Path $EnvFile
$supabaseUrl = [string]$envValues['SUPABASE_URL']
$publishableKey = [string]$envValues['SUPABASE_ANON_KEY']

if (-not $supabaseUrl) {
    throw 'SUPABASE_URL is missing from the environment file.'
}
if (-not $publishableKey) {
    throw 'SUPABASE_ANON_KEY is missing from the environment file.'
}

$requestBody = @{
    installationId = 'release-smoke-test-invalid-device'
    activationToken = 'release-smoke-test-invalid-token'
} | ConvertTo-Json

$statusCode = $null
$responseBody = ''
try {
    $response = Invoke-WebRequest `
        -Uri "$($supabaseUrl.TrimEnd('/'))/functions/v1/validate-license" `
        -Method Post `
        -Headers @{
            apikey = $publishableKey
            'Content-Type' = 'application/json'
        } `
        -Body $requestBody `
        -TimeoutSec 20 `
        -UseBasicParsing
    $statusCode = [int]$response.StatusCode
    $responseBody = [string]$response.Content
}
catch {
    if (-not $_.Exception.Response) {
        throw "Could not reach Supabase: $($_.Exception.Message)"
    }

    $statusCode = [int]$_.Exception.Response.StatusCode
    $responseBody = Get-ErrorResponseBody -ErrorRecord $_
}

if ($statusCode -eq 401 -and $responseBody -match 'JWT|authorization') {
    throw 'Supabase rejected the public license request at the gateway. Confirm verify_jwt = false and redeploy validate-license with --no-verify-jwt.'
}

if ($statusCode -ne 404 -or $responseBody -notmatch 'No activation found for this device') {
    throw "Unexpected validate-license response. Status: $statusCode Body: $responseBody"
}

Write-Host 'Supabase license smoke test passed.'
Write-Host 'The request reached validate-license and returned the expected invalid-device response.'
