function Get-DatumTupleKeyValueString
{
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [hashtable]$Item,
        [string[]]$Keys
    )
    if (-not $Keys)
    {
        $Keys = $Item.Keys
    }

    $sep = '#'
    $values = foreach ($k in $Keys)
    {
        $Item[$k]
    }
    return ($values -join $sep)
}
