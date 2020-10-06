function Start-PodeAzFuncServer
{
    param (
        [Parameter(Mandatory=$true)]
        $Data
    )

    # setup any inbuilt middleware that works for azure functions
    $inbuilt_middleware = @(
        (Get-PodePublicMiddleware),
        (Get-PodeRouteValidateMiddleware),
        (Get-PodeBodyMiddleware),
        (Get-PodeCookieMiddleware)
    )

    $PodeContext.Server.Middleware = ($inbuilt_middleware + $PodeContext.Server.Middleware)

    try
    {
        try
        {
            # get the request
            $request = $Data.Request

            # setup the response
            $response = New-Object -TypeName HttpResponseContext
            $response.StatusCode = 200
            $response.Headers = @{}

            # reset event data
            $WebEvent = @{
                OnEnd = @()
                Auth = @{}
                Response = $response
                Request = $request
                Lockable = $PodeContext.Lockable
                Method = $request.Method.ToLowerInvariant()
                Query = $request.Query
                Endpoint = @{
                    Protocol = ($request.Url -split '://')[0]
                    Address = $null
                }
                ContentType = $null
                ErrorType = $null
                Cookies = @{}
                PendingCookies = @{}
                Path = [string]::Empty
                Streamed = $false
                Route = $null
                StaticContent = $null
                Timestamp = [datetime]::UtcNow
            }

            $WebEvent.Endpoint.Address = ((Get-PodeHeader -Name 'host') -split ':')[0]
            $WebEvent.ContentType = (Get-PodeHeader -Name 'content-type')

            # set the path, using static content query parameter if passed
            if (![string]::IsNullOrWhiteSpace($request.Query['static-file'])) {
                $WebEvent.Path = $request.Query['static-file']
            }
            else {
                $WebEvent.Path = "/api/$($Data.sys.MethodName)"
            }

            $WebEvent.Path = [System.Web.HttpUtility]::UrlDecode($WebEvent.Path)

            # set pode in server response header
            Set-PodeServerHeader -Type 'Kestrel'

            # invoke global and route middleware
            if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $PodeContext.Server.Middleware -Route $WebEvent.Path)) {
                if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $WebEvent.Route.Middleware))
                {
                    # invoke the route
                    if ($null -ne $WebEvent.StaticContent) {
                        if ($WebEvent.StaticContent.IsDownload) {
                            Set-PodeResponseAttachment -Path $e.Path
                        }
                        else {
                            $cachable = $WebEvent.StaticContent.IsCachable
                            Write-PodeFileResponse -Path $WebEvent.StaticContent.Source -MaxAge $PodeContext.Server.Web.Static.Cache.MaxAge -Cache:$cachable
                        }
                    }
                    else {
                        Invoke-PodeScriptBlock -ScriptBlock $WebEvent.Route.Logic -Arguments $WebEvent -Scoped
                    }
                }
            }
        }
        catch {
            $_ | Write-PodeErrorLog
            Set-PodeResponseStatus -Code 500 -Exception $_
        }
        finally {
            Update-PodeServerRequestMetrics -WebEvent $WebEvent
        }

        # invoke endware specifc to the current web event
        $_endware = ($WebEvent.OnEnd + @($PodeContext.Server.Endware))
        Invoke-PodeEndware -WebEvent $WebEvent -Endware $_endware

        # close and send the response
        Push-OutputBinding -Name Response -Value $response
    }
    catch {
        $_ | Write-PodeErrorLog
        throw $_.Exception
    }
}

function Start-PodeAwsLambdaServer
{
    param (
        [Parameter(Mandatory=$true)]
        $Data
    )

    # setup any inbuilt middleware that works for aws lambda
    $inbuilt_middleware = @(
        (Get-PodePublicMiddleware),
        (Get-PodeRouteValidateMiddleware),
        (Get-PodeBodyMiddleware),
        (Get-PodeCookieMiddleware)
    )

    $PodeContext.Server.Middleware = ($inbuilt_middleware + $PodeContext.Server.Middleware)

    try
    {
        try
        {
            # get the request
            $request = $Data

            # setup the response
            $response = @{
                StatusCode = 200
                Headers = @{}
                Body = [string]::Empty
            }

            # reset event data
            $WebEvent = @{
                OnEnd = @()
                Auth = @{}
                Response = $response
                Request = $request
                Lockable = $PodeContext.Lockable
                Path = [System.Web.HttpUtility]::UrlDecode($request.path)
                Method = $request.httpMethod.ToLowerInvariant()
                Query = $request.queryStringParameters
                Endpoint = @{
                    Protocol = $null
                    Address = $null
                }
                ContentType = $null
                ErrorType = $null
                Cookies = @{}
                PendingCookies = @{}
                Streamed = $false
                Route = $null
                StaticContent = $null
                Timestamp = [datetime]::UtcNow
            }

            $WebEvent.Endpoint.Protocol = (Get-PodeHeader -Name 'X-Forwarded-Proto')
            $WebEvent.Endpoint.Address = ((Get-PodeHeader -Name 'Host') -split ':')[0]
            $WebEvent.ContentType = (Get-PodeHeader -Name 'Content-Type')

            # set pode in server response header
            Set-PodeServerHeader -Type 'Lambda'

            # invoke global and route middleware
            if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $PodeContext.Server.Middleware -Route $WebEvent.Path)) {
                if ((Invoke-PodeMiddleware -WebEvent $WebEvent -Middleware $WebEvent.Route.Middleware))
                {
                    # invoke the route
                    if ($null -ne $WebEvent.StaticContent) {
                        if ($WebEvent.StaticContent.IsDownload) {
                            Set-PodeResponseAttachment -Path $e.Path
                        }
                        else {
                            $cachable = $WebEvent.StaticContent.IsCachable
                            Write-PodeFileResponse -Path $WebEvent.StaticContent.Source -MaxAge $PodeContext.Server.Web.Static.Cache.MaxAge -Cache:$cachable
                        }
                    }
                    else {
                        Invoke-PodeScriptBlock -ScriptBlock $WebEvent.Route.Logic -Arguments $WebEvent -Scoped
                    }
                }
            }
        }
        catch {
            $_ | Write-PodeErrorLog
            Set-PodeResponseStatus -Code 500 -Exception $_
        }
        finally {
            Update-PodeServerRequestMetrics -WebEvent $WebEvent
        }

        # invoke endware specifc to the current web event
        $_endware = ($WebEvent.OnEnd + @($PodeContext.Server.Endware))
        Invoke-PodeEndware -WebEvent $WebEvent -Endware $_endware

        # close and send the response
        if (![string]::IsNullOrWhiteSpace($response.ContentType)) {
            Set-PodeHeader -Name 'Content-Type' -Value $response.ContentType
        }

        return (@{
            'statusCode' = $response.StatusCode;
            'headers' = $response.Headers;
            'body' = $response.Body;
        } | ConvertTo-Json -Depth 10 -Compress) 
    }
    catch {
        $_ | Write-PodeErrorLog
        throw $_.Exception
    }
}