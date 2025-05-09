[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Suppressing this rule because Script Analyzer does not understand Pester syntax.')]
param ()

BeforeDiscovery {
    try
    {
        if (-not (Get-Module -Name 'DscResource.Test'))
        {
            # Assumes dependencies has been resolved, so if this module is not available, run 'noop' task.
            if (-not (Get-Module -Name 'DscResource.Test' -ListAvailable))
            {
                # Redirect all streams to $null, except the error stream (stream 2)
                & "$PSScriptRoot/../../build.ps1" -Tasks 'noop' 3>&1 4>&1 5>&1 6>&1 > $null
            }

            # If the dependencies has not been resolved, this will throw an error.
            Import-Module -Name 'DscResource.Test' -Force -ErrorAction 'Stop'
        }
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -ResolveDependency -Tasks build" first.'
    }

    <#
        Need to define that variables here to be used in the Pester Discover to
        build the ForEach-blocks.
    #>
    $script:dscResourceFriendlyName = 'DnsClientNrptGlobal'
    $script:dscResourceName = "DSC_$($script:dscResourceFriendlyName)"
}

BeforeAll {
    # Need to define the variables here which will be used in Pester Run.
    $script:dscModuleName = 'NetworkingDsc'
    $script:dscResourceFriendlyName = 'DnsClientNrptGlobal'
    $script:dscResourceName = "DSC_$($script:dscResourceFriendlyName)"

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:dscModuleName `
        -DSCResourceName $script:dscResourceName `
        -ResourceType 'Mof' `
        -TestType 'Integration'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers\CommonTestHelper.psm1')
}

AfterAll {
    # Remove module common test helper.
    Get-Module -Name 'CommonTestHelper' -All | Remove-Module -Force

    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}


Describe 'DnsClientNrptGlobal Integration Tests' {
    BeforeAll {
        # Backup the existing settings
        $script:currentDnsClientNrptGlobal = Get-DnsClientNrptGlobal

        # Set the DNS Client Global settings to known values
        Set-DnsClientNrptGlobal `
            -EnableDAForAllNetworks 'Disable' `
            -QueryPolicy 'Disable' `
            -SecureNameQueryFallback 'Disable'

        $configData = @{
            AllNodes = @(
                @{
                    NodeName                = 'localhost'
                    EnableDAForAllNetworks  = 'EnableAlways'
                    QueryPolicy             = 'QueryBoth'
                    SecureNameQueryFallback = 'FallbackSecure'
                }
            )
        }

        $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:dscResourceName).config.ps1"
        . $configFile
    }

    AfterAll {
        # Clean up
        Set-DnsClientNrptGlobal `
            -EnableDAForAllNetworks $script:currentDnsClientNrptGlobal.EnableDAForAllNetworks `
            -QueryPolicy $script:currentDnsClientNrptGlobal.QueryPolicy `
            -SecureNameQueryFallback $script:currentDnsClientNrptGlobal.SecureNameQueryFallback
    }

    Describe "$($script:dscResourceName)_Integration" {
        AfterEach {
            Wait-ForIdleLcm
        }

        It 'Should compile and apply the MOF without throwing' {
            {
                & "$($script:dscResourceName)_Config" `
                    -OutputPath $TestDrive `
                    -ConfigurationData $configData
                Start-DscConfiguration `
                    -Path $TestDrive `
                    -ComputerName localhost `
                    -Wait `
                    -Verbose `
                    -Force
            } | Should -Not -Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should -Not -Throw
        }

        Context 'When testing each of the parameter values' {
            BeforeAll {
                # Get the DNS Client Global Settings details
                $DnsClientNrptGlobalNew = Get-DnsClientNrptGlobal
            }

            It 'Should have the correct value for <_>' -ForEach @(
                'EnableDAForAllNetworks',
                'QueryPolicy',
                'SecureNameQueryFallback'
            ) {
                $parameterCurrentValue = (Get-Variable -Name DnsClientNrptGlobalNew).value.$_
                $parameterNewValue = (Get-Variable -Name configData).Value.AllNodes[0].$_

                $parameterCurrentValue | Should -Be $parameterNewValue
            }
        }
    }
}
