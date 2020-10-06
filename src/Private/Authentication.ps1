function Get-PodeAuthBasicType
{
    return {
        param($e, $options)

        # get the auth header
        $header = (Get-PodeHeader -Name 'Authorization')
        if ($null -eq $header) {
            return @{
                Message = 'No Authorization header found'
                Code = 401
            }
        }

        # ensure the first atom is basic (or opt override)
        $atoms = $header -isplit '\s+'
        if ($atoms.Length -lt 2) {
            return @{
                Message = 'Invalid Authorization header'
                Code = 400
            }
        }

        if ($atoms[0] -ine $options.HeaderTag) {
            return @{
                Message = "Header is not for $($options.HeaderTag) Authorization"
                Code = 400
            }
        }

        # decode the auth header
        try {
            $enc = [System.Text.Encoding]::GetEncoding($options.Encoding)
        }
        catch {
            return @{
                Message = 'Invalid encoding specified for Authorization'
                Code = 400
            }
        }

        try {
            $decoded = $enc.GetString([System.Convert]::FromBase64String($atoms[1]))
        }
        catch {
            return @{
                Message = 'Invalid Base64 string found in Authorization header'
                Code = 400
            }
        }

        # validate and return user/result
        $index = $decoded.IndexOf(':')
        $username = $decoded.Substring(0, $index)
        $password = $decoded.Substring($index + 1)

        # return data for calling validator
        return @($username, $password)
    }
}

function Get-PodeAuthClientCertificateType
{
    return {
        param($e, $options)
        $cert = $e.Request.ClientCertificate

        # ensure we have a client cert
        if ($null -eq $cert) {
            return @{
                Message = 'No client certificate supplied'
                Code = 401
            }
        }

        # ensure the cert has a thumbprint
        if ([string]::IsNullOrWhiteSpace($cert.Thumbprint)) {
            return @{
                Message = 'Invalid client certificate supplied'
                Code = 401
            }
        }

        # ensure the cert hasn't expired, or has it even started
        $now = [datetime]::Now
        if (($cert.NotAfter -lt $now) -or ($cert.NotBefore -gt $now)) {
            return @{
                Message = 'Invalid client certificate supplied'
                Code = 401
            }
        }

        # return data for calling validator
        return @($cert, $e.Request.ClientCertificateErrors)
    }
}

function Get-PodeAuthBearerType
{
    return {
        param($e, $options)

        # get the auth header
        $header = (Get-PodeHeader -Name 'Authorization')
        if ($null -eq $header) {
            return @{
                Message = 'No Authorization header found'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType invalid_request)
                Code = 400
            }
        }

        # ensure the first atom is bearer
        $atoms = $header -isplit '\s+'
        if ($atoms.Length -lt 2) {
            return @{
                Message = 'Invalid Authorization header'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType invalid_request)
                Code = 400
            }
        }

        if ($atoms[0] -ine 'Bearer') {
            return @{
                Message = 'Authorization header is not Bearer'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType invalid_request)
                Code = 400
            }
        }

        # return token for calling validator
        return @($atoms[1].Trim())
    }
}

function Get-PodeAuthBearerPostValidator
{
    return {
        param($e, $token, $result, $options)

        # if there's no user, fail with challenge
        if (($null -eq $result) -or ($null -eq $result.User)) {
            return @{
                Message = 'User not found'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType invalid_token)
                Code = 401
            }
        }

        # check for an error and description
        if (![string]::IsNullOrWhiteSpace($result.Error)) {
            return @{
                Message = 'Authorization failed'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType $result.Error -ErrorDescription $result.ErrorDescription)
                Code = 401
            }
        }

        # check the scopes
        $hasAuthScopes = (($null -ne $options.Scopes) -and ($options.Scopes.Length -gt 0))
        $hasTokenScope = ![string]::IsNullOrWhiteSpace($result.Scope)

        # 403 if we have auth scopes but no token scope
        if ($hasAuthScopes -and !$hasTokenScope) {
            return @{
                Message = 'Invalid Scope'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType insufficient_scope)
                Code = 403
            }
        }

        # 403 if we have both, but token not in auth scope
        if ($hasAuthScopes -and $hasTokenScope -and ($options.Scopes -notcontains $result.Scope)) {
            return @{
                Message = 'Invalid Scope'
                Challenge = (New-PodeAuthBearerChallenge -Scopes $options.Scopes -ErrorType insufficient_scope)
                Code = 403
            }
        }

        # return result
        return $result
    }
}

function New-PodeAuthBearerChallenge
{
    param(
        [Parameter()]
        [string[]]
        $Scopes,

        [Parameter()]
        [ValidateSet('', 'invalid_request', 'invalid_token', 'insufficient_scope')]
        [string]
        $ErrorType,

        [Parameter()]
        [string]
        $ErrorDescription
    )

    $items = @()
    if (($null -ne $Scopes) -and ($Scopes.Length -gt 0)) {
        $items += "scope=`"$($Scopes -join ' ')`""
    }

    if (![string]::IsNullOrWhiteSpace($ErrorType)) {
        $items += "error=`"$($ErrorType)`""
    }

    if (![string]::IsNullOrWhiteSpace($ErrorDescription)) {
        $items += "error_description=`"$($ErrorDescription)`""
    }

    return ($items -join ', ')
}

function Get-PodeAuthDigestType
{
    return {
        param($e, $options)

        # get the auth header - send challenge if missing
        $header = (Get-PodeHeader -Name 'Authorization')
        if ($null -eq $header) {
            return @{
                Message = 'No Authorization header found'
                Challenge = (New-PodeAuthDigestChallenge)
                Code = 401
            }
        }

        # if auth header isn't digest send challenge
        $atoms = $header -isplit '\s+'
        if ($atoms.Length -lt 2) {
            return @{
                Message = 'Invalid Authorization header'
                Code = 400
            }
        }

        if ($atoms[0] -ine 'Digest') {
            return @{
                Message = 'Authorization header is not Digest'
                Challenge = (New-PodeAuthDigestChallenge)
                Code = 401
            }
        }

        # parse the other atoms of the header (after the scheme), return 400 if none
        $params = ConvertFrom-PodeAuthDigestHeader -Parts ($atoms[1..$($atoms.Length - 1)])
        if ($params.Count -eq 0) {
            return @{
                Message = 'Invalid Authorization header'
                Code = 400
            }
        }

        # if no username then 401 and challenge
        if ([string]::IsNullOrWhiteSpace($params.username)) {
            return @{
                Message = 'Authorization header is missing username'
                Challenge = (New-PodeAuthDigestChallenge)
                Code = 401
            }
        }

        # return 400 if domain doesnt match request domain
        if ($e.Path -ine $params.uri) {
            return @{
                Message = 'Invalid Authorization header'
                Code = 400
            }
        }

        # return data for calling validator
        return @($params.username, $params)
    }
}

function Get-PodeAuthDigestPostValidator
{
    return {
        param($e, $username, $params, $result, $options)

        # if there's no user or password, fail with challenge
        if (($null -eq $result) -or ($null -eq $result.User) -or [string]::IsNullOrWhiteSpace($result.Password)) {
            return @{
                Message = 'User not found'
                Challenge = (New-PodeAuthDigestChallenge)
                Code = 401
            }
        }

        # generate the first hash
        $hash1 = Invoke-PodeMD5Hash -Value "$($params.username):$($params.realm):$($result.Password)"

        # generate the second hash
        $hash2 = Invoke-PodeMD5Hash -Value "$($e.Method.ToUpperInvariant()):$($params.uri)"

        # generate final hash
        $final = Invoke-PodeMD5Hash -Value "$($hash1):$($params.nonce):$($params.nc):$($params.cnonce):$($params.qop):$($hash2)"

        # compare final hash to client response
        if ($final -ne $params.response) {
            return @{
                Message = 'Hashes failed to match'
                Challenge = (New-PodeAuthDigestChallenge)
                Code = 401
            }
        }

        # hashes are valid, remove password and return result
        $result.Remove('Password') | Out-Null
        return $result
    }
}

function ConvertFrom-PodeAuthDigestHeader
{
    param(
        [Parameter()]
        [string[]]
        $Parts
    )

    if (($null -eq $Parts) -or ($Parts.Length -eq 0)) {
        return @{}
    }

    $obj = @{}
    $value = ($Parts -join ' ')

    @($value -isplit ',(?=(?:[^"]|"[^"]*")*$)') | ForEach-Object {
        if ($_ -imatch '(?<name>\w+)=["]?(?<value>[^"]+)["]?$') {
            $obj[$Matches['name']] = $Matches['value']
        }
    }

    return $obj
}

function New-PodeAuthDigestChallenge
{
    $items = @('qop="auth"', 'algorithm="MD5"', "nonce=`"$(New-PodeGuid -Secure -NoDashes)`"")
    return ($items -join ', ')
}

function Get-PodeAuthFormType
{
    return {
        param($e, $options)

        # get user/pass keys to get from payload
        $userField = $options.Fields.Username
        $passField = $options.Fields.Password

        # get the user/pass
        $username = $e.Data.$userField
        $password = $e.Data.$passField

        # if either are empty, fail auth
        if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
            return @{
                Message = 'Username or Password not supplied'
                Code = 401
            }
        }

        # return data for calling validator
        return @($username, $password)
    }
}

function Get-PodeAuthUserFileMethod
{
    return {
        param($username, $password, $options)

        # load the file
        $users = (Get-Content -Path $options.FilePath -Raw | ConvertFrom-Json)

        # find the user by username - only use the first one
        $user = @(foreach ($_user in $users) {
            if ($_user.Username -ieq $username) {
                $_user
                break
            }
        })[0]

        # fail if no user
        if ($null -eq $user) {
            return @{ Message = 'You are not authorised to access this website' }
        }

        # check the user's password
        if (![string]::IsNullOrWhiteSpace($options.HmacSecret)) {
            $hash = Invoke-PodeHMACSHA256Hash -Value $password -Secret $options.HmacSecret
        }
        else {
            $hash = Invoke-PodeSHA256Hash -Value $password
        }

        if ($user.Password -ne $hash) {
            return @{ Message = 'You are not authorised to access this website' }
        }

        # convert the user to a hashtable
        $user = @{
            Name = $user.Name
            Username = $user.Username
            Email = $user.Email
            Groups = $user.Groups
            Metadata = $user.Metadata
        }

        # is the user valid for any users/groups?
        if (!(Test-PodeAuthUserGroups -User $user -Users $options.Users -Groups $options.Groups)) {
            return @{ Message = 'You are not authorised to access this website' }
        }

        # return user
        return @{
            User = $user
        }
    }
}

function Get-PodeAuthWindowsADMethod
{
    return {
        param($username, $password, $options)

        # validate and retrieve the AD user
        $noGroups = $options.NoGroups
        $openLdap = $options.OpenLDAP

        $result = Get-PodeAuthADResult `
            -Server $options.Server `
            -Domain $options.Domain `
            -Username $username `
            -Password $password `
            -NoGroups:$noGroups `
            -OpenLDAP:$openLdap

        # if there's a message, fail and return the message
        if (![string]::IsNullOrWhiteSpace($result.Message)) {
            return $result
        }

        # if there's no user, then, err, oops
        if (Test-PodeIsEmpty $result.User) {
            return @{ Message = 'An unexpected error occured' }
        }

        # is the user valid for any users/groups?
        if (Test-PodeAuthUserGroups -User $result.User -Users $options.Users -Groups $options.Groups) {
            return $result
        }

        # else, they shall not pass!
        return @{ Message = 'You are not authorised to access this website' }
    }
}

function Get-PodeAuthWindowsADIISMethod
{
    return {
        param($token, $options)

        # get the close handler
        $win32Handler = Add-Type -Name Win32CloseHandle -PassThru -MemberDefinition @'
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool CloseHandle(IntPtr handle);
'@

        try {
            # parse the auth token and get the user
            $winAuthToken = [System.IntPtr][Int]"0x$($token)"
            $winIdentity = New-Object System.Security.Principal.WindowsIdentity($winAuthToken, 'Windows')

            # get user and domain
            $username = ($winIdentity.Name -split '\\')[-1]
            $domain = ($winIdentity.Name -split '\\')[0]

            # create base user object
            $user = @{
                UserType = 'Domain'
                AuthenticationType = $winIdentity.AuthenticationType
                DistinguishedName = [string]::Empty
                Username = $username
                Name = [string]::Empty
                Email = [string]::Empty
                Fqdn = [string]::Empty
                Domain = $domain
                Groups = @()
            }

            # if the domain isn't local, attempt AD user
            if (![string]::IsNullOrWhiteSpace($domain) -and (@('.', $env:COMPUTERNAME) -inotcontains $domain)) {
                # get the server's fdqn (and name/email)
                try {
                    # Open ADSISearcher and change context to given domain
                    $searcher = [adsisearcher]""
                    $searcher.SearchRoot = [adsi]"LDAP://$($domain)"
                    $searcher.Filter = "ObjectSid=$($winIdentity.User.Value.ToString())"

                    # Query the ADSISearcher for the above defined SID
                    $ad = $searcher.FindOne()
                    
                    # Save it to our existing array for later usage
                    $user.DistinguishedName = @($ad.Properties.distinguishedname)[0]
                    $user.Name = @($ad.Properties.name)[0]
                    $user.Email = @($ad.Properties.mail)[0]
                    $user.Fqdn = (Get-PodeADServerFromDistinguishedName -DistinguishedName $user.DistinguishedName)
                }
                finally {
                    Close-PodeDisposable -Disposable $searcher
                }

                try {
                    if (!$options.NoGroups) {

                        # open a new connection
                        $result = (Open-PodeAuthADConnection -Server $user.Fqdn -Domain $domain)
                        if (!$result.Success) {
                            return @{ Message = "Failed to connect to Domain Server '$($user.Fqdn)' of $domain for $($user.DistinguishedName)." }
                        }

                        # get the connection
                        $connection = $result.Connection

                        # get the users groups
                        $user.Groups = (Get-PodeAuthADGroups -Connection $connection -DistinguishedName $user.DistinguishedName)
                    }
                }
                finally {
                    if ($null -ne $connection) {
                        Close-PodeDisposable -Disposable $connection.Searcher
                        Close-PodeDisposable -Disposable $connection.Entry -Close
                    }
                }
            }

            # otherwise, get details of local user
            else {
                # get the user's name and groups
                try {
                    $user.UserType = 'Local'

                    if (!$options.NoLocalCheck) {
                        $localUser = $winIdentity.Name -replace '\\', '/'
                        $ad = [adsi]"WinNT://$($localUser)"
                        $user.Name = @($ad.FullName)[0]

                        # dirty, i know :/ - since IIS runs using pwsh, the InvokeMember part fails
                        # we can safely call windows powershell here, as IIS is only on windows.
                        if (!$options.NoGroups) {
                            $cmd = "`$ad = [adsi]'WinNT://$($localUser)'; @(`$ad.Groups() | Foreach-Object { `$_.GetType().InvokeMember('Name', 'GetProperty', `$null, `$_, `$null) })"
                            $user.Groups = [string[]](powershell -c $cmd)
                        }
                    }
                }
                finally {
                    Close-PodeDisposable -Disposable $ad -Close
                }
            }
        }
        catch {
            $_ | Write-PodeErrorLog
            return @{ Message = 'Failed to retrieve user using Authentication Token' }
        }
        finally {
            $win32Handler::CloseHandle($winAuthToken)
        }

        # is the user valid for any users/groups?
        if (Test-PodeAuthUserGroups -User $user -Users $options.Users -Groups $options.Groups) {
            return @{ User = $user }
        }

        # else, they shall not pass!
        return @{ Message = 'You are not authorised to access this website' }
    }
}

function Test-PodeAuthUserGroups
{
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]
        $User,

        [Parameter()]
        [string[]]
        $Users,

        [Parameter()]
        [string[]]
        $Groups
    )

    $haveUsers = (($null -ne $Users) -and ($Users.Length -gt 0))
    $haveGroups = (($null -ne $Groups) -and ($Groups.Length -gt 0))

    # if there are no groups/users supplied, return user is valid
    if (!$haveUsers -and !$haveGroups) {
        return $true
    }

    # before checking supplied groups, is the user in the supplied list of authorised users?
    if ($haveUsers -and (@($Users) -icontains $User.Username)) {
        return $true
    }

    # if there are groups supplied, check the user is a member of one
    if ($haveGroups) {
        foreach ($group in $Groups) {
            if (@($User.Groups) -icontains $group) {
                return $true
            }
        }
    }

    return $false
}

function Get-PodeAuthMiddlewareScript
{
    return {
        param($e, $opts)

        # get the auth method
        $auth = Find-PodeAuth -Name $opts.Name

        # route options for using sessions
        $sessionless = $auth.Sessionless
        $usingSessions = (!(Test-PodeIsEmpty $e.Session))
        $useHeaders = [bool]($e.Session.Properties.UseHeaders)
        $loginRoute = $opts.Login

        # check for logout command
        if ($opts.Logout) {
            Remove-PodeAuthSession -Event $e

            if ($useHeaders) {
                return (Set-PodeAuthStatus -StatusCode 401 -Sessionless:$sessionless)
            }
            else {
                $auth.Failure.Url = (Protect-PodeValue -Value $auth.Failure.Url -Default $e.Request.Url.AbsolutePath)
                return (Set-PodeAuthStatus -StatusCode 302 -Failure $auth.Failure -Sessionless:$sessionless)
            }
        }

        # if the session already has a user/isAuth'd, then skip auth
        if ($usingSessions -and !(Test-PodeIsEmpty $e.Session.Data.Auth.User) -and $e.Session.Data.Auth.IsAuthenticated) {
            $e.Auth = $e.Session.Data.Auth
            return (Set-PodeAuthStatus -Success $auth.Success -LoginRoute:$loginRoute -Sessionless:$sessionless)
        }

        # check if the login flag is set, in which case just return and load a login get-page
        if ($loginRoute -and !$useHeaders -and ($e.Method -ieq 'get')) {
            if (!(Test-PodeIsEmpty $e.Session.Data.Auth)) {
                Revoke-PodeSession -Session $e.Session
            }

            return $true
        }

        try {
            # run auth scheme script to parse request for data
            $_args = @($e) + @($auth.Scheme.Arguments)
            if ($null -ne $auth.Scheme.ScriptBlock.UsingVariables) {
                $_args = @($auth.Scheme.ScriptBlock.UsingVariables.Value) + $_args
            }

            $result = (Invoke-PodeScriptBlock -ScriptBlock $auth.Scheme.ScriptBlock.Script -Arguments $_args -Return -Splat)

            # if data is a hashtable, then don't call validator (parser either failed, or forced a success)
            if ($result -isnot [hashtable]) {
                $original = $result

                $_args = @($result) + @($auth.Arguments)
                if ($auth.PassEvent) {
                    $_args = @($e) + $_args
                }

                if ($null -ne $auth.UsingVariables) {
                    $_args = @($auth.UsingVariables.Value) + $_args
                }

                $result = (Invoke-PodeScriptBlock -ScriptBlock $auth.ScriptBlock -Arguments $_args -Return -Splat)

                # if we have user, then run post validator if present
                if ([string]::IsNullOrWhiteSpace($result.Code) -and !(Test-PodeIsEmpty $auth.Scheme.PostValidator.Script)) {
                    $_args = @($e) + @($original) + @($result) + @($auth.Scheme.Arguments)
                    if ($null -ne $auth.Scheme.PostValidator.UsingVariables) {
                        $_args = @($auth.Scheme.PostValidator.UsingVariables.Value) + $_args
                    }

                    $result = (Invoke-PodeScriptBlock -ScriptBlock $auth.Scheme.PostValidator.Script -Arguments $_args -Return -Splat)
                }
            }
        }
        catch {
            $_ | Write-PodeErrorLog
            return (Set-PodeAuthStatus -StatusCode 500 -Description $_.Exception.Message -Failure $auth.Failure -Sessionless:$sessionless)
        }

        # if there is no result, return false (failed auth)
        if ((Test-PodeIsEmpty $result) -or (Test-PodeIsEmpty $result.User)) {
            $_code = (Protect-PodeValue -Value $result.Code -Default 401)

            # set the www-auth header
            $validCode = (($_code -eq 401) -or ![string]::IsNullOrWhiteSpace($result.Challenge))
            $validHeaders = (($null -eq $result.Headers) -or !$result.Headers.ContainsKey('WWW-Authenticate'))

            if ($validCode -and $validHeaders) {
                $_wwwHeader = Get-PodeAuthWwwHeaderValue -Name $auth.Scheme.Name -Realm $auth.Scheme.Realm -Challenge $result.Challenge
                if (![string]::IsNullOrWhiteSpace($_wwwHeader)) {
                    Set-PodeHeader -Name 'WWW-Authenticate' -Value $_wwwHeader
                }
            }

            return (Set-PodeAuthStatus `
                -StatusCode $_code `
                -Description $result.Message `
                -Headers $result.Headers `
                -Failure $auth.Failure `
                -Success $auth.Success `
                -LoginRoute:$loginRoute `
                -Sessionless:$sessionless)
        }

        # assign the user to the session, and wire up a quick method
        $e.Auth = @{}
        $e.Auth.User = $result.User
        $e.Auth.IsAuthenticated = $true
        $e.Auth.Store = !$sessionless

        # continue
        return (Set-PodeAuthStatus -Headers $result.Headers -Success $auth.Success -LoginRoute:$loginRoute -Sessionless:$sessionless)
    }
}

function Get-PodeAuthWwwHeaderValue
{
    param(
        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Realm,

        [Parameter()]
        [string]
        $Challenge
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [string]::Empty
    }

    $header = $Name
    if (![string]::IsNullOrWhiteSpace($Realm)) {
        $header += " realm=`"$($Realm)`""
    }

    if (![string]::IsNullOrWhiteSpace($Challenge)) {
        $header += ", $($Challenge)"
    }

    return $header
}

function Remove-PodeAuthSession
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Event
    )

    # blank out the auth
    $Event.Auth = @{}

    # if a session auth is found, blank it
    if (!(Test-PodeIsEmpty $Event.Session.Data.Auth)) {
        $Event.Session.Data.Remove('Auth')
    }

    # Delete the session (remove from store, blank it, and remove from Response)
    Revoke-PodeSession -Session $Event.Session
}

function Set-PodeAuthStatus
{
    param (
        [Parameter()]
        [int]
        $StatusCode = 0,

        [Parameter()]
        [string]
        $Description,

        [Parameter()]
        [hashtable]
        $Headers,

        [Parameter()]
        [hashtable]
        $Failure,

        [Parameter()]
        [hashtable]
        $Success,

        [switch]
        $LoginRoute,

        [switch]
        $Sessionless
    )

    # if we have any headers, set them
    if (($null -ne $Headers) -and ($Headers.Count -gt 0)) {
        foreach ($name in $Headers.Keys) {
            Set-PodeHeader -Name $name -Value $Headers[$name]
        }
    }

    # if a statuscode supplied, assume failure
    if ($StatusCode -gt 0)
    {
        # override description with the failureMessage if supplied
        $Description = (Protect-PodeValue -Value $Failure.Message -Default $Description)

        # add error to flash
        if ($LoginRoute -and !$Sessionless -and ![string]::IsNullOrWhiteSpace($Description)) {
            Add-PodeFlashMessage -Name 'auth-error' -Message $Description
        }

        # check if we have a failure url redirect
        if (![string]::IsNullOrWhiteSpace($Failure.Url)) {
            Move-PodeResponseUrl -Url $Failure.Url
        }
        else {
            Set-PodeResponseStatus -Code $StatusCode -Description $Description
        }

        return $false
    }

    # if no statuscode, success, so check if we have a success url redirect (but only for auto-login routes)
    if ($LoginRoute -and ![string]::IsNullOrWhiteSpace($Success.Url)) {
        Move-PodeResponseUrl -Url $Success.Url
        return $false
    }

    return $true
}

function Get-PodeADServerFromDistinguishedName
{
    param(
        [Parameter()]
        [string]
        $DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return [string]::Empty
    }

    $parts = @($DistinguishedName -split ',')
    $name = @()

    foreach ($part in $parts) {
        if ($part -imatch '^DC=(?<name>.+)$') {
            $name += $Matches['name']
        }
    }

    return ($name -join '.')
}

function Get-PodeAuthADResult
{
    param (
        [Parameter()]
        [string]
        $Server,

        [Parameter()]
        [string]
        $Domain,

        [Parameter()]
        [string]
        $Username,

        [Parameter()]
        [string]
        $Password,

        [switch]
        $NoGroups,

        [switch]
        $OpenLDAP
    )

    try
    {
        # validate the user's AD creds
        $result = (Open-PodeAuthADConnection -Server $Server -Domain $Domain -Username $Username -Password $Password -OpenLDAP:$OpenLDAP)
        if (!$result.Success) {
            return @{ Message = 'Invalid credentials supplied' }
        }

        # get the connection
        $connection = $result.Connection

        # get the user
        $user = (Get-PodeAuthADUser -Connection $connection -Username $Username -OpenLDAP:$OpenLDAP)
        if ($null -eq $user) {
            return @{ Message = 'User not found in Active Directory' }
        }

        # get the users groups
        $groups = @()
        if (!$NoGroups) {
            $groups = (Get-PodeAuthADGroups -Connection $connection -DistinguishedName $user.DistinguishedName -OpenLDAP:$OpenLDAP)
        }

        # return the user
        return @{
            User = @{
                UserType = 'Domain'
                AuthenticationType = 'LDAP'
                DistinguishedName = $user.DistinguishedName
                Username = ($Username -split '\\')[-1]
                Name = $user.Name
                Email = $user.Email
                Fqdn = $Server
                Domain = $Domain
                Groups = $groups
            }
        }
    }
    finally {
        if ((Test-PodeIsWindows) -and !$OpenLDAP -and ($null -ne $connection)) {
            Close-PodeDisposable -Disposable $connection.Searcher
            Close-PodeDisposable -Disposable $connection.Entry -Close
        }
    }
}

function Open-PodeAuthADConnection
{
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Server,

        [Parameter()]
        [string]
        $Domain,

        [Parameter()]
        [string]
        $Username,

        [Parameter()]
        [string]
        $Password,

        [Parameter()]
        [ValidateSet('LDAP', 'WinNT')]
        [string]
        $Protocol = 'LDAP',

        [switch]
        $OpenLDAP
    )

    $result = $true
    $connection = $null

    # validate the user's AD creds
    if ((Test-PodeIsWindows) -and !$OpenLDAP) {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            $ad = (New-Object System.DirectoryServices.DirectoryEntry "$($Protocol)://$($Server)")
        }
        else {
            $ad = (New-Object System.DirectoryServices.DirectoryEntry "$($Protocol)://$($Server)", "$($Username)", "$($Password)")
        }

        if (Test-PodeIsEmpty $ad.distinguishedName) {
            $result = $false
        }
        else {
            $connection = @{
                Entry = $ad
            }
        }
    }
    else {
        $dcName = "DC=$(($Server -split '\.') -join ',DC=')"
        $query = (Get-PodeAuthADQuery -Username $Username)
        $hostname = "$($Protocol)://$($Server)"

        $user = $Username
        if (!$Username.StartsWith($Domain)) {
            $user = "$($Domain)\$($Username)"
        }

        (ldapsearch -x -LLL -H "$($hostname)" -D "$($user)" -w "$($Password)" -b "$($dcName)" "$($query)" dn) | Out-Null
        if (!$? -or ($LASTEXITCODE -ne 0)) {
            $result = $false
        }
        else {
            $connection = @{
                Hostname = $hostname
                Username = $user
                DCName = $dcName
                Password = $Password
            }
        }
    }

    return @{
        Success = $result
        Connection = $connection
    }
}

function Get-PodeAuthADQuery
{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Username
    )

    return "(&(objectCategory=person)(samaccountname=$($Username)))"
}

function Get-PodeAuthADUser
{
    param(
        [Parameter(Mandatory=$true)]
        $Connection,

        [Parameter(Mandatory=$true)]
        [string]
        $Username,

        [switch]
        $OpenLDAP
    )

    $query = (Get-PodeAuthADQuery -Username $Username)

    # generate query to find user
    if ((Test-PodeIsWindows) -and !$OpenLDAP) {
        $Connection.Searcher = New-Object System.DirectoryServices.DirectorySearcher $Connection.Entry
        $Connection.Searcher.filter = $query

        $result = $Connection.Searcher.FindOne().Properties
        if (Test-PodeIsEmpty $result) {
            return $null
        }

        $user = @{
            DistinguishedName = @($result.distinguishedname)[0]
            Name = @($result.name)[0]
            Email = @($result.mail)[0]
        }
    }
    else {
        $result = (ldapsearch -x -LLL -H "$($Connection.Hostname)" -D "$($Connection.Username)" -w "$($Connection.Password)" -b "$($Connection.DCName)" "$($query)" name mail)
        if (!$? -or ($LASTEXITCODE -ne 0)) {
            return $null
        }

        $user = @{
            DistinguishedName = (Get-PodeOpenLdapValue -Lines $result -Property 'dn')
            Name = (Get-PodeOpenLdapValue -Lines $result -Property 'name')
            Email = (Get-PodeOpenLdapValue -Lines $result -Property 'mail')
        }
    }

    return $user
}

function Get-PodeOpenLdapValue
{
    param(
        [Parameter()]
        [string[]]
        $Lines,

        [Parameter()]
        [string]
        $Property,

        [switch]
        $All
    )

    foreach ($line in $Lines) {
        if ($line -imatch "^$($Property)\:\s+(?<$($Property)>.+)$") {
            # return the first found
            if (!$All) {
                return $Matches[$Property]
            }

            # return array of all
            $Matches[$Property]
        }
    }
}

function Get-PodeAuthADGroups
{
    param (
        [Parameter(Mandatory=$true)]
        $Connection,

        [Parameter()]
        [string]
        $DistinguishedName,

        [switch]
        $OpenLDAP
    )

    # create the query
    $query = "(member:1.2.840.113556.1.4.1941:=$($DistinguishedName))"
    $groups = @()

    # get the groups
    if ((Test-PodeIsWindows) -and !$OpenLDAP) {
        if ($null -eq $Connection.Searcher) {
            $Connection.Searcher = New-Object System.DirectoryServices.DirectorySearcher $Connection.Entry
        }

        $Connection.Searcher.PropertiesToLoad.Add('samaccountname') | Out-Null
        $Connection.Searcher.filter = $query
        $groups = @($Connection.Searcher.FindAll().Properties.samaccountname)
    }
    else {
        $result = (ldapsearch -x -LLL -H "$($Connection.Hostname)" -D "$($Connection.Username)" -w "$($Connection.Password)" -b "$($Connection.DCName)" "$($query)" samaccountname)
        $groups = (Get-PodeOpenLdapValue -Lines $result -Property 'sAMAccountName' -All)
    }

    return $groups
}

function Get-PodeAuthDomainName
{
    if (Test-PodeIsUnix) {
        $dn = (dnsdomainname)
        if ([string]::IsNullOrWhiteSpace($dn)) {
            $dn = (/usr/sbin/realm list --name-only)
        }

        return $dn
    }
    else {
        $domain = $env:USERDNSDOMAIN
        if ([string]::IsNullOrWhiteSpace($domain)) {
            $domain = (Get-CimInstance -Class Win32_ComputerSystem -Verbose:$false).Domain
        }

        return $domain
    }
}

function Find-PodeAuth
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    return $PodeContext.Server.Authentications[$Name]
}

function Test-PodeAuth
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    return $PodeContext.Server.Authentications.ContainsKey($Name)
}