# Get RegionalAndLanguageSettingsAccount for current or last logged-in user
Write-Output "Checking Regional and Language Settings Account..."

function Get-RegionalAccount {
    # Try current user first
    $currentUserKey = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Common\LanguageResources\LocalCache"
    if (Test-Path $currentUserKey) {
        $val = (Get-ItemProperty -Path $currentUserKey -Name "RegionalAndLanguageSettingsAccount" -ErrorAction SilentlyContinue).RegionalAndLanguageSettingsAccount
        if ($val) { return $val }
    }

    # If not found, check all user profiles in HKEY_USERS
    $userProfiles = Get-ChildItem "Registry::HKEY_USERS\" | Where-Object { $_.PSChildName -match '^S-1-5-21-' }
    foreach ($profile in $userProfiles) {
        $subkey = "Registry::HKEY_USERS\$($profile.PSChildName)\Software\Microsoft\Office\16.0\Common\LanguageResources\LocalCache"
        if (Test-Path $subkey) {
            $val = (Get-ItemProperty -Path $subkey -Name "RegionalAndLanguageSettingsAccount" -ErrorAction SilentlyContinue).RegionalAndLanguageSettingsAccount
            if ($val) { return $val }
        }
    }

    return $null
}

$result = Get-RegionalAccount

if ($result) {
    Write-Output "RegionalAndLanguageSettingsAccount found: $result"
} else {
    Write-Output "No RegionalAndLanguageSettingsAccount found in registry."
}
