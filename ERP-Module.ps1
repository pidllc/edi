
function Get-UpcomingOrders () {
    $BASE = "https://your-erp.example.com"  # adjust to your base URL

    # --- Read cookies from the Netscape cookie jar file ---
    $cookieJarPath = "/tmp/erp.jar"
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    Get-Content $cookieJarPath | ForEach-Object {
        if ($_ -notmatch '^#') {
            $parts = $_ -split "`t"
            if ($parts.Count -ge 7) {
                $cookie = New-Object System.Net.Cookie($parts[5], $parts[6])
                $cookie.Domain = $parts[0]
                $cookie.Path   = $parts[2]
                $session.Cookies.Add($cookie)
            }
        }
    }

    # --- Build the request (GET with query params) ---
    $uri = "$BASE/api/orders?ship_start=2026-06-01&ship_end=2026-06-30&per_page=1000"

    $response = Invoke-RestMethod -Uri $uri -Method Get -WebSession $session

    # --- Equivalent of | jq '.orders' ---
    $response.orders   

    curl -s -b /tmp/erp.jar --get "$BASE/api/orders" \
    --data-urlencode 'ship_start=2026-06-01' \
    --data-urlencode 'ship_end=2026-06-30' \
    --data-urlencode 'per_page=1000' | jq '.orders'
}