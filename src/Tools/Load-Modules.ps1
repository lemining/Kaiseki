Write-Host "## Loading Modules ##"

cd $psake.context.originalDirectory

# Ignore node_modules - this is due to how nodejs handles dependencies (nested folder structure).
# Path exceeding 260 characters will break PowerShell execution (https://github.com/nodejs/node-v0.x-archive/issues/6960)
Get-ChildItem Tasks-*.ps1 -Exclude "node_modules" -ErrorAction SilentlyContinue -Recurse -File | % {
    Write-Host Loading $_.Name
    Include $_
}

#Global properties
properties {
    $OutputPath = "CiOutput"
    $ArtefactPath = "CiArtefact"
    # Hard code for now.
    $AssemblyVersion = "1.0.0.0"
}

Task Default -depends Clean,New-CsvOutputCollection,New-CiOutFolder,Transform-InjectBuildInfo,
    Execute-PreBuildAnalysis,Execute-MsBuild,Execute-PostBuildAnalysis,
    Execute-Nunit,Execute-ReportGenerator,
    New-NugetPackagesFromSpecFiles,Write-CsvOutputCollection,
    Copy-Nunit,Copy-TestAssemblies,Copy-KaisekiModules


Write-Host "## Loading Modules > Done ##"
Write-Host
Write-Host
