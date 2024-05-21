# Read the content of x.txt file
$fileContent = Get-Content -Path "result-production.txt" -Raw

# Split the content into individual deployment blocks
$deploymentBlocks = $fileContent -split '---'

# Loop through each deployment block
foreach ($block in $deploymentBlocks)
{
    # Extract deployment name
    $deploymentName = ($block -split "`n")[0] -replace 'Deployment: '

    Write-Host "Pulling Docker images for deployment: $deploymentName"

    # Extract image names and tags
    $images = $block -split "`n" | Select-String -Pattern '^gcr\.io.*' | ForEach-Object {
        $imageName, $imageTag = $_ -split ':'
        [PSCustomObject]@{
            Name = $imageName
            Tag = $imageTag
        }
    }

    # Pull Docker images
    foreach ($image in $images)
    {
        $imageNameWithTag = "$( $image.Name ):$( $image.Tag )"
        Write-Host "Pulling Docker image: $imageNameWithTag"
        docker pull $imageNameWithTag
        $newImageName = $imageNameWithTag -replace 'gcr\.io/devops-218510/', ''
        docker tag "$( $imageNameWithTag )" "..repo../$( $newImageName )"

        $newImageNameWithoutTag = $newImageName -replace ':.*', ''

        $repoExists = aws ecr describe-repositories --repository-names ${newImageNameWithoutTag} --profile devops
        if (-not $repoExists)
        {
            Write-Output "Creating ECR repository: ${newImageNameWithoutTag}"
            aws ecr create-repository --repository-name ${newImageNameWithoutTag} --profile devops
        }

        docker push "..repo../$( $newImageName )"
        docker rmi "..repo../$( $newImageName )"
        docker rmi "$( $imageNameWithTag )"
    }
}
