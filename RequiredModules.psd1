@{
    # Set up a mini virtual environment...
    PSDependOptions             = @{
        AddToPath  = $true
        Target     = 'output\RequiredModules'
        Parameters = @{
        }
    }

    InvokeBuild                 = 'latest'
    PSScriptAnalyzer            = 'latest'
    Pester                      = 'latest'
    'DscResource.Test'          = 'latest'
    'DscResource.AnalyzerRules' = 'latest'
    #'DscResource.Common'        = 'latest'
    Plaster                     = 'latest'
    ModuleBuilder               = '3.1.8'
    ChangelogManagement         = 'latest'
    Sampler                     = 'latest'
    'Sampler.GitHubTasks'       = 'latest'

    ProtectedData               = 'latest'
    'Datum.ProtectedData'       = 'latest'
    'Datum.InvokeCommand'       = 'latest'

}
