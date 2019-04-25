<#
This script organises Plex files according to the item user rating;
currently, only one Library type is supported.

It supports two storage locations, primary and secondary
Items with a rating above the threshold set below are moved to the primary location
Items with a rating equal to or below the threshold are moved to the secondary location

The rating is expressed as stars in the Plex UI (1 to 5) to a resolution of half-stars and is stored as a value between 0 and 10.
2 stars   = rating 4
2.5 stars = rating 5

Requires a Plex authentication token
Temporary: https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/
Permanent: https://forums.plex.tv/discussion/129922/how-to-request-a-x-plex-token-token-for-your-app/p1

Plex URL commands are documented here:
https://support.plex.tv/articles/201638786-plex-media-server-url-commands/

Use this code to list Library Sections:

[xml]$librarySections = (Invoke-WebRequest -Uri "$plex/library/sections/?X-Plex-Token=$token").Content
foreach ($section in $librarySections.MediaContainer.Directory)
{
    Write-Host $section.key $section.type $section.title
}

In the following example, we're working with movies which are key 2

#>

$plex  = 'http://myserveraddress:32400'
$token = 'mytokengoeshere'
$primaryPath = "\\pathto\primary\location"
$secondaryPath = "\\pathto\secondary\location"
$ratingThreshold = 6 # 3 stars
$sectionKey = 2

#-- load functions

function Move-Path {
    param($sourceFile, $destinationPath)

    if( -Not (Test-Path -Path $destinationPath ) )
    {
        Write-Host "Creating $destinationPath"
        New-Item -ItemType directory -Path $destinationPath -Force | Out-Null
    }
    else
    {
        Write-Host "$destinationPath exists"
    }

    Write-Host "Moving $sourceFile to $destinationPath"
    Move-Item -Path $sourceFile -Destination $destinationPath -Force
    Write-Host "Done"
}

function Delete-EmptyDirectories {
    param($folderName)
    Write-Host "Deleting empty directories from $folderName"
    dir $folderName -Directory -recurse | where {-NOT $_.GetFiles("*","AllDirectories")} | del -recurse
    Write-Host "Done"
}

#-- done loading functions
$movieList = @{}
[xml]$movies = (Invoke-WebRequest -Uri "$plex/library/sections/$sectionKey/all?X-Plex-Token=$token").Content
foreach ($movie in $movies.MediaContainer.Video)
{
    $userRating = [int]$movie.userRating

    if ($movie.userRating -and $userRating -le $ratingThreshold -and $movie.Media.Part.file -inotlike "*$secondaryPath*")
    {
        Write-Host "`n"
        Write-Host $movie.title
        Write-Host "Rating: $userRating"
        Write-Host $movie.Media.Part.file

        $sourceFile = $movie.Media.Part.file
        $destination = Join-Path -Path $secondaryPath -ChildPath (Split-Path(Split-Path $sourceFile -Parent) -Leaf)

        Write-Host "Move to secondary"
        Move-Path -sourceFile $sourceFile -destinationPath $destination

        $movieList.Add($movie.title, $userRating/2)
    }
    elseif ($movie.userRating -and $userRating -gt $ratingThreshold -and $movie.Media.Part.file -inotlike "*$primaryPath*")
    {
        Write-Host "`n"
        Write-Host $movie.title
        Write-Host "Rating: $userRating"
        Write-Host $movie.Media.Part.file

        $sourceFile = $movie.Media.Part.file
        $destination = Join-Path -Path $primaryPath -ChildPath (Split-Path(Split-Path $sourceFile -Parent) -Leaf)

        Write-Host "Move to primary"
        Move-Path -sourceFile $sourceFile -destinationPath $destination  
        
        $movieList.Add($movie.title, $userRating/2)  
    }
}

Write-Host "Completed organsing. Removing empty directories..."
Delete-EmptyDirectories -folderName $primaryPath
Delete-EmptyDirectories -folderName $secondaryPath

Write-Host "Asking Plex to start a scan"
$plexResponse = (Invoke-WebRequest -Uri "$plex/library/sections/$sectionKey/refresh?X-Plex-Token=$token").statuscode
if ($plexResponse -ne 200)
{
    Write-Host "Plex did not respond to the refresh request"
}
else
{
    Write-Host "Plex responded OK"
}

Write-Host "Complete!"
Write-Host "Updated items:" $movieList.Count

if ($movieList.Count -gt 0)
{
    $message = "Plex items updated: " + $movieList.Count + "`n`n"
    foreach ($key in $movieList.Keys)
    {
        $s = ''
        if ($movieList["$key"] -gt 1)
        {
            $s = 's'
        }
        $message += $key + " (" + $movieList["$key"] + " star$s)`n"
    }
    Write-Output $message
}
