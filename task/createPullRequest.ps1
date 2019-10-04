function RunTask
{
   [CmdletBinding()]
   param(
      [string] $sourceBranch,
      [string] $targetBranch,
      [string] $title,
      [string] $description,
      [string] $reviewers
   )

   Trace-VstsEnteringInvocation $MyInvocation
   try {
       # Get inputs
       $sourceBranch = Get-VstsInput -Name 'sourceBranch' -Require
       $targetBranch = Get-VstsInput -Name 'targetBranch' -Require
       $Name = 'githubEndpoint'

        # Get the URL.
        $description = Get-LocString -Key PSLIB_EndpointUrl0 -ArgumentList $Name
        $key = "ENDPOINT_URL_$Name"
        $url = Get-VaultValue -Description $description -Key $key -Require:$Require
        Write-host $url

        # Get the auth object.
        $description = Get-LocString -Key PSLIB_EndpointAuth0 -ArgumentList $Name
        $key = "ENDPOINT_AUTH_$Name"
        if ($auth = (Get-VaultValue -Description $description -Key $key -Require:$Require)) {
            $auth = ConvertFrom-Json -InputObject $auth
        }
        Write-host $auth

        # Get the data.
        $description = "'$Name' service endpoint data"
        $key = "ENDPOINT_DATA_$Name"
        if ($data = (Get-VaultValue -Description $description -Key $key)) {
            $data = ConvertFrom-Json -InputObject $data
        }
        Write-host $data

       
       
       $title = Get-VstsInput -Name 'title' -Require
       $description = Get-VstsInput -Name 'description'
       $reviewers = Get-VstsInput -Name 'reviewers'
       if(!$sourceBranch.Contains("refs"))
       {
           $sourceBranch = "refs/heads/$sourceBranch"
       }

       # If the target branch is only one branch
       if(!$targetBranch.Contains('*'))
       {
           $targetBranch = "refs/heads/$targetBranch"     
           CheckReviewersAndCreatePR -sourceBranch $sourceBranch -targetBranch $targetBranch -title $title -description $description -reviewers $reviewers
        }

       # If the target branch is like feature/*
       else
       {
           Set-Location $env:Build_SourcesDirectory
           $branches = git branch -a
           $branches.ForEach({
                if($_ -match ($targetBranch.Split('/')[0]))
                {
                        $newTargetBranch = $_.Split('/')[2] + "/" + $_.Split('/')[3]
                        $newTargetBranch = "refs/heads/$newTargetBranch"
                        CheckReviewersAndCreatePR -sourceBranch $sourceBranch -targetBranch $newTargetBranch -title $title -description $description -reviewers $reviewers
                }
           })
       }

   } finally {
       Trace-VstsLeavingInvocation $MyInvocation
   }
}

function CreatePullRequest($body, $reviewers)
{
    Write-Host "The source branch is: $($body.sourceRefName)"
    Write-Host "The target branch is: $($body.targetRefName)"
    Write-Host "The title is: $($body.title)"
    Write-Host "The description is: $($body.description)"
    if($body.Keys -contains "reviewers")
    {
        Write-Host "The reviewers are: $($reviewers.Split(';'))"
    }
    $head = @{ Authorization = "Bearer $env:System_AccessToken" }
    $jsonBody = ConvertTo-Json $body
    Write-Debug $jsonBody
    $url = "$env:System_TeamFoundationCollectionUri$env:System_TeamProject/_apis/git/repositories/$env:Build_Repository_Name/pullrequests?api-version=5.0"
    Write-Debug $url
    try 
    {
        $response =  Invoke-RestMethod -Uri $url -Method Post -Headers $head -Body $jsonBody -ContentType application/json
        if($response -ne $Null) # If the response not null - the create PR succeeded
        {
            Write-Host "*************************"
            Write-Host "******** Success ********"
            Write-Host "*************************"
            Write-Host "Pull Request $($response.pullRequestId) created."
        }
    }
    catch 
    {
        try { $errorMessage = ($_ | ConvertFrom-Json).message }
        catch { }
        # If the error contains TF401179 it's mean that there is alredy a PR for the branches, so I display a warning
        if($errorMessage -match "TF401179") 
        {
            Write-Warning $errorMessage
        }
        else # If there is an error - fail the task
        {
            try { Write-Warning $errorMessage }
            catch { }
            Write-Error $_
            Write-Error $_.Exception.Message
        }
    }
}

function CheckReviewersAndCreatePR($sourceBranch, $targetBranch, $title, $description, $reviewers)
{
    if($reviewers -ne "")
    {
        $url = "$($env:System_TeamFoundationCollectionUri)_apis/userentitlements?api-version=5.0-preview.2"
        $url = $url.Replace("//dev","//vsaex.dev")
        Write-Debug $url
        $head = @{ Authorization = "Bearer $env:System_AccessToken" }
        $users = Invoke-RestMethod -Uri $url -Method Get -ContentType application/json -Headers $head
        $reviewers = $reviewers.Split(';')
        $usersId = @()
        ForEach($reviewer in $reviewers)
        {
              $userId = $users.items.Where({ $_.user.mailAddress -eq $reviewer }).id
              $usersId += @{ id = "$userId" }
        }
        $body = @{
            sourceRefName = "$sourceBranch"
            targetRefName = "$targetBranch"
            title = "$title"
            description = "$description"
            reviewers = @( $usersId )
        }
        CreatePullRequest -body $body -reviewers $reviewers

    }
    else
    {
        $body = @{
            sourceRefName = "$sourceBranch"
            targetRefName = "$targetBranch"
            title = "$title"
            description = "$description"
        }
        CreatePullRequest -body $body
    }
}

RunTask
