# Check if yaml module is imported, if not, import it
if (-not (Get-Module -Name powershell-yaml -ListAvailable))
{
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
}
Import-Module -Name powershell-yaml

# Change current directory to 'apps'
Set-Location -Path ".\apps"

# List all service directories
$serviceDirectories = Get-ChildItem -Directory

# Function to parse kustomization.yaml file
function ParseKustomizationFile
{
    param (
        [string]$filePath
    )

    # Read content from the file
    $content = Get-Content -Path $filePath -Raw

    # Parse YAML content
    $yamlObject = $content | ConvertFrom-Yaml

    # Access the 'images' property and output 'newName' and 'newTag' for each image
    foreach ($image in $yamlObject.images)
    {
        if ($image.newName)
        {
            $imageName = $image.newName
        }
        else
        {
            $imageName = $image.name
        }
        $imageTag = $image.newTag

        $newImageName = $imageName -replace 'gcr\.io/devops-218510/', ''


        Write-Output "  newName: $( $imageName )"
        Write-Output "  newTag: $( $image.newTag )"

        Write-Output "Pulling Docker image: $( $imageName ):$( $image.newTag )"
        docker pull "$( $imageName ):$( $image.newTag )"
        docker tag "$( $imageName ):$( $image.newTag )" "954254635138.dkr.ecr.eu-west-1.amazonaws.com/$( $newImageName ):$( $image.newTag )"

        $repoExists = aws ecr describe-repositories --repository-names ${newImageName} --profile devops
        if (-not $repoExists)
        {
            Write-Output "Creating ECR repository: ${newImageName}"
            aws ecr create-repository --repository-name ${newImageName} --profile devops
        }

        docker push "954254635138.dkr.ecr.eu-west-1.amazonaws.com/$( $newImageName ):$( $image.newTag )"
        docker rmi "954254635138.dkr.ecr.eu-west-1.amazonaws.com/$( $newImageName ):$( $image.newTag )"
        docker rmi "$( $imageName ):$( $image.newTag )"
    }
}

# Output service directory names
foreach ($serviceDirectory in $serviceDirectories)
{
    $serviceName = $serviceDirectory.Name
    Write-Host "Service: $serviceName"

    # Enter service directory
    Set-Location -Path $serviceName

    # Check if 'overlays' directory exists
    if (Test-Path -Path "overlays" -PathType Container)
    {
        Write-Host "  List of folders in 'overlays' directory:"

        # Enter 'overlays' directory
        Set-Location -Path "overlays"

        # List all folder names in 'overlays' directory
        $overlayFolders = Get-ChildItem -Directory | Select-Object -ExpandProperty Name
        foreach ($overlayFolder in $overlayFolders)
        {
            Write-Host "  - $overlayFolder"
            # Enter each overlay folder
            Set-Location -Path $overlayFolder

            # Check if 'kustomization.yaml' file exists
            $kustomizationFilePath = "kustomization.yaml"
            if (Test-Path -Path $kustomizationFilePath -PathType Leaf)
            {
                Write-Host "    Parsing 'kustomization.yaml' file for ${overlayFolder}:"
                ParseKustomizationFile -filePath $kustomizationFilePath
            }
            else
            {
                Write-Host "    'kustomization.yaml' file not found in $overlayFolder"
            }

            # Return back to 'overlays' directory
            Set-Location -Path ..
        }

        # Return back to service directory
        Set-Location -Path ..
    }
    else
    {
        Write-Host "  'overlays' directory not found in service: $serviceName"
    }

    # Return back to 'apps' directory
    Set-Location -Path ..
}
