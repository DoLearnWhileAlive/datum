function Test-DatumKnockout
{
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [hashtable]$DiffItem,
        [hashtable]$RefKnockoutItem,
        [regex]$KnockoutPrefixMatcher
    )

    foreach ($k in $RefKnockoutItem.Keys)
    {
        $refVal = $RefKnockoutItem[$k] -replace $KnockoutPrefixMatcher
        $diffVal = $DiffItem[$k]
        if ($diffVal -ne $refVal)
        {
            return $false
        }
    }
    return $true
}
