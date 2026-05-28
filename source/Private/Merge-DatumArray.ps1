function Merge-DatumArray
{
    [OutputType([System.Collections.Generic.List[object]])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]
        $ReferenceArray,

        [Parameter(Mandatory = $true)]
        [object]
        $DifferenceArray,

        [Parameter()]
        [hashtable]
        $Strategy = @{},

        [Parameter()]
        [hashtable]
        $ChildStrategies = @{
            '^.*' = $Strategy
        },

        [Parameter(Mandatory = $true)]
        [string]
        $StartingPath
    )

    Write-Debug -Message "`tMerge-DatumArray -StartingPath <$StartingPath>"
    $hashArrayStrategy = $Strategy.merge_hash_array
    Write-Debug -Message "`t`tHash Array Strategy: $hashArrayStrategy"

    $tupleKeys = if ($Strategy.merge_options.tuple_keys)
    {
        [string[]]$Strategy.merge_options.tuple_keys
    }
    else
    {
        @()
    }

    $mergedArray = [System.Collections.Generic.List[object]]::new()

    # Early exit if not an array of hashtables
    if (-not $ReferenceArray -as [hashtable[]])
    {
        return , $mergedArray
    }

    # MostSpecific strategy: return reference array as-is (with optional sorting)
    if (-not $hashArrayStrategy -or $hashArrayStrategy -match 'MostSpecific')
    {
        Write-Debug -Message "`t`tMerge_hash_arrays Disabled. value: $hashArrayStrategy"
        if ($Strategy.sort_merged_arrays -and $tupleKeys.Count -gt 0)
        {
            $ReferenceArray = $ReferenceArray | Sort-Object -Property $tupleKeys
        }
        return , $ReferenceArray
    }

    Write-Debug -Message "`t`tMERGING Array of Hashtables"

    $ReferenceArray = @(
        foreach ($referenceItem in $ReferenceArray)
        {
            # Shallow copy reference items to avoid converted tuple key values
            # land in original DatumTree. Otherwise follow-up nodes merge the
            # same tuple key values as the first node.
            $clonedReferenceItem = [ordered]@{} + $referenceItem
            foreach ($prop in $tupleKeys)
            {
                if ($clonedReferenceItem.Contains($prop))
                {
                    # Make sure property values are converted before comparing
                    if (Invoke-DatumHandler -InputObject $clonedReferenceItem[$prop] -DatumHandlers $Datum.__Definition.DatumHandlers -Result ([ref]$result))
                    {
                        $clonedReferenceItem[$prop] = ConvertTo-Datum -InputObject $result -DatumHandlers $Datum.__Definition.DatumHandlers
                    }
                }
            }
            $clonedReferenceItem
        }
    )

    $DifferenceArray = @(
        foreach ($differenceItem in $DifferenceArray)
        {
            # Shallow copy difference items to avoid converted tuple key values
            # land in original DatumTree. Otherwise follow-up nodes merge the
            # same tuple key values as the first node.
            $clonedDifferenceItem = [ordered]@{} + $differenceItem
            foreach ($prop in $tupleKeys)
            {
                if ($clonedDifferenceItem.Contains($prop))
                {
                    # Make sure property values are converted before comparing
                    if (Invoke-DatumHandler -InputObject $clonedDifferenceItem[$prop] -DatumHandlers $Datum.__Definition.DatumHandlers -Result ([ref]$result))
                    {
                        $clonedDifferenceItem[$prop] = ConvertTo-Datum -InputObject $result -DatumHandlers $Datum.__Definition.DatumHandlers
                    }
                }
            }
            $clonedDifferenceItem
        }
    )

    # Precompute knockout regex for identifying knockout-prefixed values
    $knockoutPrefixMatcher = if ($Strategy.merge_options.knockout_prefix)
    {
        '^' + [regex]::Escape($Strategy.merge_options.knockout_prefix)
    }
    else
    {
        $null
    }

    $result = $null

    # Precompute list of knockout reference items
    # Stores only properties with knockout values to efficiently check during merge
    $knockoutReferenceItems = @(
        foreach ($referenceItem in $ReferenceArray)
        {
            $knockoutItem = @{}
            foreach ($prop in $tupleKeys)
            {
                if ($referenceItem.Contains($prop))
                {
                    if ($knockoutPrefixMatcher)
                    {
                        if ($referenceItem[$prop] -match $knockoutPrefixMatcher)
                        {
                            $knockoutItem[$prop] = $referenceItem[$prop]
                        }
                    }
                }
                if ($knockoutItem.Count -gt 0)
                {
                    $knockoutItem
                }
            }
        }
    )

    switch -Regex ($hashArrayStrategy)
    {
        # Sum/Add strategy: combine all items from both arrays
        '^Sum|^Add'
        {
            foreach ($referenceItem in $ReferenceArray)
            {
                $mergedArray.Add($referenceItem)
            }
            foreach ($differenceItem in $DifferenceArray)
            {
                $mergedArray.Add($differenceItem)
            }
        }

        # Deep/Merge strategy: merge items with matching tuple keys
        '^Deep|^Merge'
        {
            Write-Debug -Message "`t`t`tStrategy for Array Items: Merge Hash By tuple`r`n"

            # Build differenceItem index hashtable for O(1) lookups
            # Key = composite tuple key string, Value = the difference item
            $diffIndex = @{}
            foreach ($differenceItem in $DifferenceArray)
            {
                $key = Get-DatumTupleKeyValueString $differenceItem $tupleKeys
                $diffIndex[$key] = $differenceItem
            }

            # Track which difference keys have been used for merging
            $usedDiffKeys = @{}

            # Process reference items: merge with matching difference items or keep as-is
            foreach ($referenceItem in $ReferenceArray)
            {
                # Determine which keys to use for comparison
                $compareKeys = if ($tupleKeys.Count -gt 0)
                {
                    $tupleKeys
                }
                else
                {
                    Write-Debug -Message "`t`t`t ..No PropertyName defined: Use ReferenceItem Keys"
                    $referenceItem.Keys
                }
                $key = Get-DatumTupleKeyValueString $referenceItem $compareKeys

                if ($diffIndex.ContainsKey($key))
                {
                    # Match found - merge the items
                    $usedDiffKeys[$key] = $true
                    $paramsMergeHt = @{
                        ParentPath          = $StartingPath
                        Strategy            = $Strategy
                        ReferenceHashtable  = $referenceItem
                        DifferenceHashtable = $diffIndex[$key]
                        ChildStrategies     = $ChildStrategies
                    }
                    $mergedArray.Add((Merge-Hashtable @paramsMergeHt))
                }
                else
                {
                    # No match - keep reference item as-is
                    $mergedArray.Add($referenceItem)
                }
            }

            # Process remaining difference items that weren't merged
            foreach ($differenceItem in $DifferenceArray)
            {
                # Check if this item should be knocked out
                $shouldKnockout = $false
                foreach ($knockoutReferenceItem in $knockoutReferenceItems)
                {
                    if (Test-DatumKnockout -DiffItem $differenceItem -RefKnockoutItem $knockoutReferenceItem -KnockoutPrefixMatcher $knockoutPrefixMatcher)
                    {
                        $shouldKnockout = $true
                        break
                    }
                }
                if ($shouldKnockout)
                {
                    continue
                }

                $key = Get-DatumTupleKeyValueString $differenceItem $tupleKeys
                # Only add if not already merged with a reference item
                if (-not $usedDiffKeys.ContainsKey($key))
                {
                    $mergedArray.Add($differenceItem)
                }
            }
        }

        # Unique strategy: keep only unique items across both arrays based on tuple keys
        '^Unique'
        {
            Write-Debug -Message "`t`t`tSelecting Unique Hashes accross both arrays based on Property tuples"

            # Track seen keys to ensure uniqueness
            $seenKeys = @{}

            # Process reference items first
            foreach ($referenceItem in $ReferenceArray)
            {
                # Determine which keys to use for comparison
                $compareKeys = if ($tupleKeys.Count -gt 0)
                {
                    $tupleKeys
                }
                else
                {
                    Write-Debug -Message "`t`t`t ..No PropertyName defined: Use ReferenceItem Keys"
                    $referenceItem.Keys
                }
                $key = Get-DatumTupleKeyValueString $referenceItem $compareKeys
                if (-not $seenKeys.ContainsKey($key))
                {
                    $seenKeys[$key] = $true
                    $mergedArray.Add($referenceItem)
                }
            }

            # Process difference items, skipping knockouts and duplicates
            foreach ($differenceItem in $DifferenceArray)
            {
                # Check if this item should be knocked out
                $shouldKnockout = $false
                foreach ($knockoutReferenceItem in $knockoutReferenceItems)
                {
                    if (Test-DatumKnockout -DiffItem $differenceItem -RefKnockoutItem $knockoutReferenceItem -KnockoutPrefixMatcher $knockoutPrefixMatcher)
                    {
                        $shouldKnockout = $true
                        break
                    }
                }
                if ($shouldKnockout)
                {
                    continue
                }

                $key = Get-DatumTupleKeyValueString $differenceItem $tupleKeys
                # Only add if not already seen (ensures uniqueness)
                if (-not $seenKeys.ContainsKey($key))
                {
                    $seenKeys[$key] = $true
                    $mergedArray.Add($differenceItem)
                }
            }
        }
    }

    return , $mergedArray
}
