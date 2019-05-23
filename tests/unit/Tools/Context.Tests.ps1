$path = $MyInvocation.MyCommand.Path
$src = (Split-Path -Parent -Path $path) -ireplace '[\\/]tests[\\/]unit[\\/]', '/src/'
Get-ChildItem "$($src)/*.ps1" | Resolve-Path | ForEach-Object { . $_ }

$PodeContext = @{ 'Server' = $null; }

Describe 'Get-PodeConfiguration' {
    It 'Returns JSON config' {
        $json = '{ "settings": { "port": 90 } }'
        $PodeContext.Server = @{ 'Configuration' = ($json | ConvertFrom-Json) }
        $config = Get-PodeConfiguration
        $config | Should Not Be $null
        $config.settings.port | Should Be 90
    }
}

Describe 'Config' {
    It 'Returns JSON config' {
        $json = '{ "settings": { "port": 90 } }'
        $PodeContext.Server = @{ 'Configuration' = ($json | ConvertFrom-Json) }
        $config = Config
        $config | Should Not Be $null
        $config.settings.port | Should Be 90
    }
}

Describe 'State' {
    Context 'Invalid parameters supplied' {
        It 'Throw null name parameter error' {
            { State -Action Set -Name $null } | Should Throw 'The argument is null or empty'
        }

        It 'Throw empty name parameter error' {
            { State -Action Set -Name ([string]::Empty) } | Should Throw 'The argument is null or empty'
        }

        It 'Throw invalid action error' {
            { State -Action 'MOO' -Name 'test' } | Should Throw "Cannot validate argument on parameter 'Action'"
        }
    }

    Context 'Valid parameters supplied' {
        It 'Returns null for no context' {
            State -Action Set -Name 'test' | Should Be $null
        }

        It 'Returns null for no shared state in context' {
            $PodeContext.Server = @{ 'State' = $null }
            State -Action Set -Name 'test' | Should Be $null
        }

        It 'Sets and returns an object' {
            $PodeContext.Server = @{ 'State' = @{} }
            $result = State -Action Set -Name 'test' -Object 7

            $result | Should Be 7
            $PodeContext.Server.State['test'] | Should Be 7
        }

        It 'Gets an object' {
            $PodeContext.Server = @{ 'State' = @{ 'test' = 8 } }
            State -Action Get -Name 'test' | Should Be 8
        }

        It 'Removes an object' {
            $PodeContext.Server = @{ 'State' = @{ 'test' = 8 } }
            State -Action Remove -Name 'test' | Should Be 8
            $PodeContext.Server.State['test'] | Should Be $null
        }
    }
}

Describe 'Listen' {
    Context 'Invalid parameters supplied' {
        It 'Throw null IP:Port parameter error' {
            { Listen -IPPort $null -Type 'HTTP' } | Should Throw 'The argument is null or empty'
        }

        It 'Throw empty IP:Port parameter error' {
            { Listen -IPPort ([string]::Empty) -Type 'HTTP' } | Should Throw 'The argument is null or empty'
        }

        It 'Throw invalid type error for no method' {
            { Listen -IPPort '127.0.0.1' -Type 'MOO' } | Should Throw "Cannot validate argument on parameter 'Type'"
        }
    }

    Context 'Valid parameters supplied' {
        Mock Test-PodeIPAddress { return $true }
        Mock Test-IsAdminUser { return $true }

        It 'Set just a Hostname address' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP 'foo.com' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].Name | Should Be ([string]::Empty)
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].RawAddress | Should Be 'foo.com'
        }

        It 'Set Hostname address with a Name' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP 'foo.com' -Type 'HTTP' -Name 'Example'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].Name | Should Be 'Example'
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be 'foo.com'
        }

        It 'Set just a Hostname address with colon' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP 'foo.com:' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].RawAddress | Should Be 'foo.com:'
        }

        It 'Set both the Hostname address and port' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP 'foo.com:80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'foo.com'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be 'foo.com'
        }

        It 'Set just an IPv4 address' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'
        }

        It 'Set just an IPv4 address for all' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP 'all' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '0.0.0.0'
            $PodeContext.Server.Endpoints[0].RawAddress | Should Be 'all'
        }

        It 'Set just an IPv4 address with colon' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 0
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'
        }

        It 'Set just a port' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '0.0.0.0'
        }

        It 'Set just a port with colon' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP ':80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '0.0.0.0'
        }

        It 'Set both IPv4 address and port' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'
        }

        It 'Set both IPv4 address and port for all' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '*:80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1
            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '0.0.0.0'
            $PodeContext.Server.Endpoints[0].RawAddress | Should Be '*:80'
        }

        It 'Throws error for an invalid IPv4' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            { Listen -IP '256.0.0.1' -Type 'HTTP' } | Should Throw 'Invalid IP Address'

            $PodeContext.Server.Type | Should Be $null
            $PodeContext.Server.Endpoints | Should Be $null
        }

        It 'Throws error for an invalid IPv4 address with port' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            { Listen -IP '256.0.0.1:80' -Type 'HTTP' } | Should Throw 'Invalid IP Address'

            $PodeContext.Server.Type | Should Be $null
            $PodeContext.Server.Endpoints | Should Be $null
        }

        It 'Add two endpoints to listen on, of the same type' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP'
            Listen -IP 'pode.foo.com:80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 2

            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'

            $PodeContext.Server.Endpoints[1].Port | Should Be 80
            $PodeContext.Server.Endpoints[1].HostName | Should Be 'pode.foo.com'
            $PodeContext.Server.Endpoints[1].Address.ToString() | Should Be 'pode.foo.com'
        }

        It 'Add two endpoints to listen on, with different names' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP' -Name 'Example1'
            Listen -IP 'pode.foo.com:80' -Type 'HTTP' -Name 'Example2'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 2

            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].Name | Should Be 'Example1'
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'

            $PodeContext.Server.Endpoints[1].Port | Should Be 80
            $PodeContext.Server.Endpoints[1].Name | Should Be 'Example2'
            $PodeContext.Server.Endpoints[1].HostName | Should Be 'pode.foo.com'
            $PodeContext.Server.Endpoints[1].Address.ToString() | Should Be 'pode.foo.com'
        }

        It 'Add two endpoints to listen on, one of HTTP and one of HTTPS' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP'
            Listen -IP 'pode.foo.com:80' -Type 'HTTPS'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 2

            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'

            $PodeContext.Server.Endpoints[1].Port | Should Be 80
            $PodeContext.Server.Endpoints[1].HostName | Should Be 'pode.foo.com'
            $PodeContext.Server.Endpoints[1].Address.ToString() | Should Be 'pode.foo.com'
        }

        It 'Add two endpoints to listen on, but one added as they are the same' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP'
            Listen -IP '127.0.0.1:80' -Type 'HTTP'

            $PodeContext.Server.Type | Should Be 'HTTP'
            $PodeContext.Server.Endpoints | Should Not Be $null
            $PodeContext.Server.Endpoints.Length | Should Be 1

            $PodeContext.Server.Endpoints[0].Port | Should Be 80
            $PodeContext.Server.Endpoints[0].HostName | Should Be 'localhost'
            $PodeContext.Server.Endpoints[0].Address.ToString() | Should Be '127.0.0.1'
        }

        It 'Throws error when adding two endpoints of different types' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP'
            { Listen -IP 'pode.foo.com:80' -Type 'SMTP' } | Should Throw 'cannot add smtp endpoint'
        }

        It 'Throws error when adding two endpoints with the same name' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'HTTP' -Name 'Example'
            { Listen -IP 'pode.foo.com:80' -Type 'HTTP' -Name 'Example' } | Should Throw 'already been defined'
        }

        It 'Throws error when adding two SMTP endpoints' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'SMTP'
            { Listen -IP 'pode.foo.com:80' -Type 'SMTP' } | Should Throw 'already been defined'
        }

        It 'Throws error when adding two TCP endpoints' {
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            Listen -IP '127.0.0.1:80' -Type 'TCP'
            { Listen -IP 'pode.foo.com:80' -Type 'TCP' } | Should Throw 'already been defined'
        }

        It 'Throws an error for not running as admin' {
            Mock Test-IsAdminUser { return $false }
            $PodeContext.Server = @{ 'Endpoints' = @(); 'Type' = $null }
            { Listen -IP 'foo.com' -Type 'HTTP' } | Should Throw 'Must be running with admin'
        }
    }
}

Describe 'Script' {
    Context 'Invalid parameters supplied' {
        It 'Throw null path parameter error' {
            { Script -Path $null } | Should Throw 'The argument is null or empty'
        }

        It 'Throw empty path parameter error' {
            { Script -Path ([string]::Empty) } | Should Throw 'The argument is null or empty'
        }
    }

    Context 'Valid parameters supplied' {
        Mock 'Resolve-Path' { return @{ 'Path' = 'c:/some/file.txt' } }
        Mock 'Test-PodePath' { return $true }

        It 'Returns null for no shared state in context' {
            $PodeContext = @{ 'RunspaceState' = [initialsessionstate]::CreateDefault() }

            Script -Path 'file.txt'

            $modules = @($PodeContext.RunspaceState.Modules)
            $modules.Length | Should Be 1
            $modules[0].Name | Should Be 'c:/some/file.txt'
        }
    }
}

Describe 'Import' {
    Context 'Invalid parameters supplied' {
        It 'Throw null path parameter error' {
            { Import -Path $null } | Should Throw 'The argument is null or empty'
        }

        It 'Throw empty path parameter error' {
            { Import -Path ([string]::Empty) } | Should Throw 'The argument is null or empty'
        }
    }

    Context 'Valid parameters supplied' {
        Mock 'Resolve-Path' { return @{ 'Path' = 'c:/some/file.txt' } }
        Mock 'Test-PodePath' { return $true }

        It 'Returns null for no shared state in context' {
            $PodeContext = @{ 'RunspaceState' = [initialsessionstate]::CreateDefault() }

            Import -Path 'file.txt'

            $modules = @($PodeContext.RunspaceState.Modules)
            $modules.Length | Should Be 1
            $modules[0].Name | Should Be 'c:/some/file.txt'
        }
    }
}

Describe 'New-PodeAutoRestartServer' {
    It 'Do not create any restart schedules' {
        Mock 'Config' { return @{} }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 0
        $PodeContext.Schedules.Count | Should Be 0
    }

    It 'Creates a timer for a period server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'period' = 180;
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 1
        $PodeContext.Schedules.Count | Should Be 0
        $PodeContext.Timers.Keys[0] | Should Be '__pode_restart_period__'
    }

    It 'Creates a schedule for a timed server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'times' = @('18:00');
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 0
        $PodeContext.Schedules.Count | Should Be 1
        $PodeContext.Schedules.Keys[0] | Should Be '__pode_restart_times__'
    }

    It 'Creates a schedule for a cron server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'crons' = @('@minutely');
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 0
        $PodeContext.Schedules.Count | Should Be 1
        $PodeContext.Schedules.Keys[0] | Should Be '__pode_restart_crons__'
    }

    It 'Creates a timer and schedule for a period and cron server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'period' = 180;
                    'crons' = @('@minutely');
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 1
        $PodeContext.Schedules.Count | Should Be 1
        $PodeContext.Timers.Keys[0] | Should Be '__pode_restart_period__'
        $PodeContext.Schedules.Keys[0] | Should Be '__pode_restart_crons__'
    }

    It 'Creates a timer and schedule for a period and timed server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'period' = 180;
                    'times' = @('18:00');
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 1
        $PodeContext.Schedules.Count | Should Be 1
        $PodeContext.Timers.Keys[0] | Should Be '__pode_restart_period__'
        $PodeContext.Schedules.Keys[0] | Should Be '__pode_restart_times__'
    }

    It 'Creates two schedules for a cron and timed server restart' {
        Mock 'Config' { return @{
            'server' = @{
                'restart'=  @{
                    'crons' = @('@minutely');
                    'times' = @('18:00');
                }
            }
        } }

        $PodeContext = @{ 'Timers' = @{}; 'Schedules' = @{}; }
        New-PodeAutoRestartServer

        $PodeContext.Timers.Count | Should Be 0
        $PodeContext.Schedules.Count | Should Be 2
    }
}