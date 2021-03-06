$path = Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
Import-Module "$($path)/src/Pode.psm1" -Force -ErrorAction Stop

# or just:
# Import-Module Pode

# create a server, flagged to generate a self-signed cert for dev/testing, but allow client certs for auth
Start-PodeServer {

    # bind to ip/port and set as https with self-signed cert
    Add-PodeEndpoint -Address * -Port 8443 -Protocol Https -SelfSigned -AllowClientCertificate

    # set view engine for web pages
    Set-PodeViewEngine -Type Pode

    # setup client cert auth
    New-PodeAuthScheme -ClientCertificate | Add-PodeAuth -Name 'Validate' -Sessionless -ScriptBlock {
        param($cert, $errors)

        # validate the thumbprint - here you would check a real cert store, or database
        if ($cert.Thumbprint -ieq '3571B3BE3CA202FA56F73691FC258E653D0874C1') {
            return @{
                User = @{
                    ID ='M0R7Y302'
                    Name = 'Morty'
                    Type = 'Human'
                }
            }
        }

        # an invalid cert
        return @{ Message = 'Invalid certificate supplied' }
    }

    # GET request for web page at "/"
    Add-PodeRoute -Method Get -Path '/' -Authentication 'Validate' -ScriptBlock {
        param($e)
        #$e.Request.ClientCertificate | out-default
        Write-PodeViewResponse -Path 'simple' -Data @{ 'numbers' = @(1, 2, 3); }
    }

    # GET request throws fake "500" server error status code
    Add-PodeRoute -Method Get -Path '/error' -Authentication 'Validate' -ScriptBlock {
        param($e)
        Set-PodeResponseStatus -Code 500
    }

}
