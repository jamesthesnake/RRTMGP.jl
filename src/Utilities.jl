module Utilities

export any_vals_less_than, any_vals_outside, reshape_for_comparison
export loc_in_array, check_range, check_extent

"""
  loc_in_array

Location of element `e` in the array `array`. If the
element is not in the array, returns -1.
"""
loc_in_array(e, array) = e in array ? findfirst(i->i==e,array) : -1

"""
    check_extent(array, s, label)

Assert array has correct size
"""
check_extent(array, s, label) = @assert all(size(array).==s)

"""
    check_range(val, minV, maxV, label)

Assert range of values is valid
"""
check_range(val, minV, maxV, label) = any(val .< minV) || any(val .> maxV) ? error(strip(label) * " values out of range.") : nothing

# Values less than a floor
any_vals_less_than(array, check_value) = minimum(array) < check_value
function any_vals_less_than(array, mask, check_value)
  temp = array[mask]
  return isempty(temp) ? false : minimum(temp) < check_value
end

# Values outside a range
function any_vals_outside(array, checkMin, checkMax)
  minValue = minimum(array)
  maxValue = maximum(array)
  return minValue < checkMin || maxValue > checkMax
end
function any_vals_outside(array, mask, checkMin, checkMax)
  temp = array[mask]
  if isempty(temp)
    return false
  end
  minValue = minimum(temp)
  maxValue = maximum(temp)
  return minValue < checkMin || maxValue > checkMax
end

function reshape_for_comparison(flux::Array{FT}, nlay::I, ncol::I, nexp::I) where {FT, I}
  temp = Array{FT}(undef,size(flux,2),size(flux,1),size(flux,3))
  for i = 1:size(flux,3)
    temp[:,:,i] = transpose(flux[:,:,i])
  end
  return reshape(temp,nlay+1,ncol,nexp)
end


end