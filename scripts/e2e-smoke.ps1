param(
    [string]$UsersUrl = "http://localhost:5101",
    [string]$CatalogUrl = "http://localhost:5102",
    [string]$PaymentsUrl = "http://localhost:5103"
)

$ErrorActionPreference = "Stop"

function Invoke-Api([string]$Method, [string]$Url, $Body = $null, [string]$Token = $null) {
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Compress } else { $null }
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $json -ContentType "application/json"
}

function Wait-OrderStatus([long]$OrderId, [string]$Token) {
    for ($i = 0; $i -lt 30; $i++) {
        $order = (Invoke-Api GET "$CatalogUrl/api/v1/orders/$OrderId" -Token $Token).value
        if ($order.status -ne "Pending") { return $order }
        Start-Sleep -Seconds 1
    }
    throw "Order $OrderId is still Pending after 30 seconds."
}

$email = "player-$([guid]::NewGuid().ToString('N').Substring(0, 8))@fcg.com"

Write-Host "1) Registering $email (publishes UserCreatedEvent -> welcome e-mail)" -ForegroundColor Cyan
Invoke-Api POST "$UsersUrl/api/v1/users/register" @{ name = "Player"; email = $email; password = "Abcdef1!" } | Out-Null

Write-Host "2) Logging in as the new user and as the default administrator" -ForegroundColor Cyan
$userToken = (Invoke-Api POST "$UsersUrl/api/v1/users/logins" @{ email = $email; password = "Abcdef1!" }).value.token
$adminToken = (Invoke-Api POST "$UsersUrl/api/v1/users/logins" @{ email = "fcg@admin.com"; password = "Fcg@Admin2026!" }).value.token

Write-Host "3) Administrator creates a cheap game (59.90) and an expensive one (199.90)" -ForegroundColor Cyan
$cheap = (Invoke-Api POST "$CatalogUrl/api/v1/games" @{ name = "Hollow Knight"; description = "Metroidvania"; price = 59.90 } $adminToken).value
$expensive = (Invoke-Api POST "$CatalogUrl/api/v1/games" @{ name = "Collector Edition"; description = "Too expensive"; price = 199.90 } $adminToken).value

Write-Host "4) Ordering the cheap game (OrderPlacedEvent -> Payments -> PaymentProcessedEvent Approved)" -ForegroundColor Cyan
$approvedOrder = (Invoke-Api POST "$CatalogUrl/api/v1/orders" @{ gameId = $cheap.id } $userToken).value
$approvedOrder = Wait-OrderStatus $approvedOrder.id $userToken
Write-Host "   Order #$($approvedOrder.id): $($approvedOrder.status)"

Write-Host "5) Ordering the expensive game (above Payments:MaxApprovedAmount -> Rejected)" -ForegroundColor Cyan
$rejectedOrder = (Invoke-Api POST "$CatalogUrl/api/v1/orders" @{ gameId = $expensive.id } $userToken).value
$rejectedOrder = Wait-OrderStatus $rejectedOrder.id $userToken
Write-Host "   Order #$($rejectedOrder.id): $($rejectedOrder.status)"

Write-Host "6) Checking the library and the payment records" -ForegroundColor Cyan
$library = (Invoke-Api GET "$CatalogUrl/api/v1/user-games" -Token $userToken).value
$payment = (Invoke-Api GET "$PaymentsUrl/api/v1/payments/orders/$($approvedOrder.id)" -Token $userToken).value
Write-Host "   Library: $(@($library.items | ForEach-Object { $_.gameName }) -join ', ')"
Write-Host "   Payment of order #$($approvedOrder.id): $($payment.status) (R$ $($payment.amount))"

$ok = $approvedOrder.status -eq "Approved" -and $rejectedOrder.status -eq "Rejected" -and $library.totalCount -eq 1
if (-not $ok) { throw "End-to-end flow failed." }

Write-Host "`nEnd-to-end flow OK. Check the NotificationsAPI logs for the welcome and purchase confirmation e-mails." -ForegroundColor Green
