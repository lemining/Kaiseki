task New-CiOutFolder -precondition {
    return !(Test-Path $OutputPath)
} {

    $newItem = New-Item -ItemType directory -Path $OutputPath
    Write-Host "> Created: $($newItem.FullName)"
}

task Clean {

    $packageFolder = (Resolve-Path .\packages)
    Write-Host "> Killing all obj and bin folders"
    Get-ChildItem -Include bin,obj -Recurse |
        ? { !$_.FullName.StartsWith($packageFolder) } |
        Remove-Item -Force -Recurse

    if (Test-Path $OutputPath) {
        Write-Host "> Killing $OutputPath"
        Remove-Item $OutputPath -Recurse -Force
    }
}

properties {
    $TargetSolution = ""
}
Task Get-TargetSolution {

	if(![string]::IsNullOrWhiteSpace($TargetSolution)) {
		Write-Host "> Looking for target solution: " $TargetSolution
		$solutions = Get-ChildItem -R -Filter $TargetSolution
	} else {
        Write-Host "> Looking for all solutions" $TargetSolution
		$solutions = Get-ChildItem *.sln
	}

    if ($solutions.count -eq 0) {
        throw "No .sln file found"
    } elseif ($solutions.count -gt 1 ) {
        Write-Host "> Following solution files found:"
        $solutions | Format-List -Property FullName
        Write-Error "Only one solution can be built at a time."
    }

    $script:solution = $solutions[0]
    Write-Host "> Solution Target: " $solutions[0].Name
}

properties {
    #$DotNetVersion = "4.0"

    #MsBuild Visual Studio Version
	$MsbVsVersion
    #MsBuild Configuration
    $MsbConfiguration = "Release"
    #MsBuild Auto Parmeterise Connection String in Web.config
    $MsbApcs = "true"
}
Task Execute-MsBuild -depends Get-TargetSolution {

    <#$regKey = "HKLM:\software\Microsoft\MSBuild\ToolsVersions\$DotNetVersion"
    $regProperty = "MSBuildToolsPath"
    $msBuildBinPath = join-path -path (Get-ItemProperty $regKey).$regProperty -childpath "msbuild.exe"
    Write-Host "> MsBuild Path: $msBuildBinPath"#>
    $MsbLog = $OutputPath + "\MsBuild.log"

    #Build configuration. Default is Release.
    $MsbConfigurationParam = "Configuration=$MsbConfiguration"

    #Auto parameterise connection string
    #Empty if true.
    $MsbApcsParam = ""
    $boolMsbApcs = [System.Convert]::ToBoolean($MsbApcs)
    if (!$boolMsbApcs) {
        $MsbApcsParam = ";AutoParameterizationWebConfigConnectionStrings=false"
    }

    #Default Visual Studio version is 12.
    $MsbVsVersionParam = ""
    if (![string]::IsNullOrWhiteSpace($MsbVsVersion)) {
        $MsbVsVersionParam = ";VisualStudioVersion=$MsbVsVersion.0"
    }
	
    $DynamicArgs = "/p:$MsbConfigurationParam$MsbApcsParam$MsbVsVersionParam"
    Write-Host "> Dynamic Args: $DynamicArgs"

    $StaticArgs = "/p:TargetProfile=Local;DeployTarget=Package;PackageLocation=CiWebDeploy\Site.zip;RunCodeAnalysis=True;DeployOnBuild=True"
    Write-Host "> Static Args: $StaticArgs"

    Write-Host "> Running MsBuild..."
    exec { msbuild $script:targetSolution.FullName $DynamicArgs $StaticArgs /t:Rebuild /t:Publish > $MsbLog }
    Write-Host "> Done running MsBuild!"
}

properties {
    $BuildTransformArgs = @{ "AssemblyVersion" = "$AssemblyVersion" }
}
Task Transform-InjectBuildInfo {

    $filesToTransform = Get-ChildItem .\ -File -Include *.bt.* -Recurse

    foreach($fileToTransform in $filesToTransform) {

        Write-Host "> Tranforming: $($fileToTransform.FullName)"
        $newPath = (Resolve-Path $fileToTransform -Relative).
            Replace(".bt.", ".")
        Write-Host "> To: $($newPath.FullName)"

        $fileToTransformContent = Get-Content $fileToTransform
        foreach($buildTransformArgsKey in $BuildTransformArgs.Keys) {
            $fileToTransformContent = $fileToTransformContent.
                Replace("#$buildTransformArgsKey#", $BuildTransformArgs[$buildTransformArgsKey])
        }
        $fileToTransformContent | Set-Content $newPath

    }
}

properties {
    $NugetBinPath = .".\.nuget\NuGet.exe"
}
Task New-NugetPackagesFromSpecFiles -depends Execute-MsBuild {
	$command = "pack"

    Write-Host "> Packing nuget packages with version number $AssemblyVersion"

    $nuspecFiles = Get-ChildItem *.nuspec -Recurse | ? {
        !($_.FullName.Contains("\packages\"))
    }

    foreach($nuspecFile in $nuspecFiles) {
        Write-Host "> Packing $($nuspecFile.FullName)"
        &"$NugetBinPath" $command $nuspecFile.FullName -Prop Version=$assemblyVersion
    }

    #Move all .nupkg files to output folder.
    Get-ChildItem *.nupkg | % {
        Move-Item $_.Name ".\$test\$($_.Name)"
    }
}