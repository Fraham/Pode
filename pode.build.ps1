param (
    [string]
    $Version = ''
)

<#
# Dependency Versions
#>

$Versions = @{
    Pester = '4.8.0'
    MkDocs = '1.0.4'
    Coveralls = '1.0.25'
    SevenZip = '18.5.0.20180730'
    Checksum = '0.2.0'
    MkDocsTheme = '4.2.0'
    PlatyPS = '0.14.0'
}

<#
# Helper Functions
#>

function Test-IsWindows
{
    $v = $PSVersionTable
    return ($v.Platform -ilike '*win*' -or ($null -eq $v.Platform -and $v.PSEdition -ieq 'desktop'))
}

function Test-IsAppVeyor
{
    return (![string]::IsNullOrWhiteSpace($env:APPVEYOR_JOB_ID))
}

function Test-Command($cmd)
{
    $path = $null

    if (Test-IsWindows) {
        $path = (Get-Command $cmd -ErrorAction Ignore)
    }
    else {
        $path = (which $cmd)
    }

    return (![string]::IsNullOrWhiteSpace($path))
}

function Invoke-Install($name, $version)
{
    if (Test-IsWindows) {
        if (Test-Command 'choco') {
            choco install $name --version $version -y
        }
    }
    else {
        if (Test-Command 'brew') {
            brew install $name
        }
        elseif (Test-Command 'apt-get') {
            sudo apt-get install $name -y
        }
        elseif (Test-Command 'yum') {
            sudo yum install $name -y
        }
    }
}


<#
# Helper Tasks
#>

# Synopsis: Stamps the version onto the Module
task StampVersion {
    (Get-Content ./src/Pode.psd1) | ForEach-Object { $_ -replace '\$version\$', $Version } | Set-Content ./src/Pode.psd1
    (Get-Content ./packers/choco/pode.nuspec) | ForEach-Object { $_ -replace '\$version\$', $Version } | Set-Content ./packers/choco/pode.nuspec
    (Get-Content ./packers/choco/tools/ChocolateyInstall.ps1) | ForEach-Object { $_ -replace '\$version\$', $Version } | Set-Content ./packers/choco/tools/ChocolateyInstall.ps1
}

# Synopsis: Generating a Checksum of the Zip
task PrintChecksum {
    if (Test-IsWindows) {
        $Script:Checksum = (checksum -t sha256 $Version-Binaries.zip)
    }
    else {
        $Script:Checksum = (shasum -a 256 ./$Version-Binaries.zip | awk '{ print $1 }').ToUpper()
    }

    Write-Host "Checksum: $($Checksum)"
}


<#
# Dependencies
#>

# Synopsis: Installs Chocolatey
task ChocoDeps -If (Test-IsWindows) {
    if (!(Test-Command 'choco')) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
}

# Synopsis: Install dependencies for packaging
task PackDeps -If (Test-IsWindows) ChocoDeps, {
    if (!(Test-Command 'checksum')) {
        Invoke-Install 'checksum' $Versions.Checksum
    }

    if (!(Test-Command '7z')) {
        Invoke-Install '7zip' $Versions.SevenZip
    }
}

# Synopsis: Install dependencies for running tests
task TestDeps {
    # install pester
    if (((Get-Module -ListAvailable Pester) | Where-Object { $_.Version -ieq $Versions.Pester }) -eq $null) {
        Write-Host 'Installing Pester'
        Install-Module -Name Pester -Scope CurrentUser -RequiredVersion $Versions.Pester -Force -SkipPublisherCheck
    }

    # install coveralls
    if (Test-IsAppVeyor)
    {
        if (((Get-Module -ListAvailable coveralls) | Where-Object { $_.Version -ieq $Versions.Coveralls }) -eq $null) {
            Write-Host 'Installing Coveralls'
            Install-Module -Name coveralls -Scope CurrentUser -RequiredVersion $Versions.Coveralls -Force -SkipPublisherCheck
        }
    }
}

# Synopsis: Install dependencies for documentation
task DocsDeps ChocoDeps, {
    # install mkdocs
    if (!(Test-Command 'mkdocs')) {
        Invoke-Install 'mkdocs' $Versions.MkDocs
    }

    $_installed = (pip list --format json --disable-pip-version-check | ConvertFrom-Json)
    if (($_installed | Where-Object { $_.name -ieq 'mkdocs-material' -and $_.version -ieq $Versions.MkDocsTheme } | Measure-Object).Count -eq 0) {
        pip install "mkdocs-material==$($Versions.MkDocsTheme)" --force-reinstall --disable-pip-version-check
    }

    # install platyps
    if (((Get-Module -ListAvailable PlatyPS) | Where-Object { $_.Version -ieq $Versions.PlatyPS }) -eq $null) {
        Write-Host 'Installing PlatyPS'
        Install-Module -Name PlatyPS -Scope CurrentUser -RequiredVersion $Versions.PlatyPS -Force -SkipPublisherCheck
    }
}


<#
# Packaging
#>

# Synopsis: Creates a Zip of the Module
task 7Zip -If (Test-IsWindows) PackDeps, StampVersion, {
    exec { & 7z -tzip a $Version-Binaries.zip ./src/* }
}, PrintChecksum

# Synopsis: Creates a Chocolately package of the Module
task ChocoPack -If (Test-IsWindows) PackDeps, StampVersion, {
    exec { choco pack ./packers/choco/pode.nuspec }
}

# Synopsis: Package up the Module
task Pack -If (Test-IsWindows) 7Zip, ChocoPack


<#
# Testing
#>

# Synopsis: Run the tests
task Test TestDeps, {
    $p = (Get-Command Invoke-Pester)
    if ($null -eq $p -or $p.Version -ine $Versions.Pester) {
        Import-Module Pester -Force -RequiredVersion $Versions.Pester
    }

    $Script:TestResultFile = "$($pwd)/TestResults.xml"

    # if appveyor, run code coverage
    if (Test-IsAppVeyor) {
        $srcFiles = (Get-ChildItem "$($pwd)/src/*.ps1" -Recurse -Force).FullName
        $Script:TestStatus = Invoke-Pester './tests/unit' -OutputFormat NUnitXml -OutputFile $TestResultFile -CodeCoverage $srcFiles -PassThru
    }
    else {
        $Script:TestStatus = Invoke-Pester './tests/unit' -OutputFormat NUnitXml -OutputFile $TestResultFile -PassThru
    }
}, PushAppVeyorTests, PushCodeCoverage, CheckFailedTests

# Synopsis: Check if any of the tests failed
task CheckFailedTests {
    if ($TestStatus.FailedCount -gt 0) {
        throw "$($TestStatus.FailedCount) tests failed"
    }
}

# Synopsis: If AppVeyor, push result artifacts
task PushAppVeyorTests -If (Test-IsAppVeyor) {
    $url = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
    (New-Object 'System.Net.WebClient').UploadFile($url, $TestResultFile)
    Push-AppveyorArtifact $TestResultFile
}

# Synopsis: If AppyVeyor, push code coverage stats
task PushCodeCoverage -If (Test-IsAppVeyor) {
    $coverage = Format-Coverage -PesterResults $Script:TestStatus -CoverallsApiToken $env:PODE_COVERALLS_TOKEN -RootFolder $pwd -BranchName $ENV:APPVEYOR_REPO_BRANCH
    Publish-Coverage -Coverage $coverage
}


<#
# Docs
#>

# Synopsis: Run the documentation locally
task Docs DocsDeps, DocsHelpBuild, {
    mkdocs serve
}

# Synopsis: Build the function help documentation
task DocsHelpBuild DocsDeps, {
    # import the local module
    Remove-Module Pode -Force -ErrorAction Ignore
    Import-Module ./src/Pode.psm1 -Force

    # build the function docs
    $path = './docs2/Functions'
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    New-MarkdownHelp -Module Pode -OutputFolder $path -Force -AlphabeticParamsOrder

    # remove the module
    Remove-Module Pode -Force -ErrorAction Ignore
}

# Synopsis: Build the documentation
task DocsBuild DocsDeps, DocsHelpBuild, {
    mkdocs build
}