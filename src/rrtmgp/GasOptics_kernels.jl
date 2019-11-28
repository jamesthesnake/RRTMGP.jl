#####
##### Numeric calculations for gas optics. Absorption and Rayleigh optical depths, source functions.
#####

PaTohPa(::Type{FT}) where FT = FT(0.01)

"""
    interpolation!(...)

Compute interpolation coefficients
for calculations of major optical depths, minor optical depths, Rayleigh,
and Planck fractions

 - `ref` reference variables, see [`Reference`](@ref)
 - `ics` interpolation coefficients, see [`InterpolationCoefficients`](@ref)

integer,                            intent(in) :: ncol,nlay
integer,                            intent(in) :: ngas,nflav,neta,npres,ntemp
integer,     dimension(2,nflav),    intent(in) :: flavor
# inputs from profile or parent function
real(FT),    dimension(ncol,nlay),        intent(in) :: play, tlay
real(FT),    dimension(ncol,nlay,0:ngas), intent(in) :: col_gas

# outputs
real(FT),    dimension(2,    nflav,ncol,nlay), intent(out) :: col_mix
real(FT),    dimension(2,2,  nflav,ncol,nlay), intent(out) :: fminor
# -----------------
# local
real(FT), dimension(ncol,nlay) :: ftemp, fpress # interpolation fraction for temperature, pressure
real(FT) :: locpress # needed to find location in pressure grid
real(FT) :: ratio_eta_half # ratio of vmrs of major species that defines eta=0.5
                           # for given flavor and reference temperature level
real(FT) :: eta, feta      # binary_species_parameter, interpolation variable for eta
real(FT) :: loceta         # needed to find location in eta grid
real(FT) :: ftemp_term
# -----------------
# local indexes
integer :: icol, ilay, iflav, igases(2), itropo, itemp
"""
function interpolation!(ics::InterpolationCoefficients{FT,I},
                        col_mix::Array{FT},
                        ncol::I,
                        nlay::I,
                        nflav::I,
                        neta::I,
                        npres::I,
                        ntemp::I,
                        flavor::Array{I},
                        ref::Reference{FT},
                        play::Array{FT},
                        tlay::Array{FT},
                        col_gas::AbstractArray{FT}) where {I<:Int,B<:Bool,FT<:AbstractFloat}
  # input dimensions
  ftemp = Array{FT}(undef, ncol, nlay)
  fpress = Array{FT}(undef, ncol, nlay)
  igases = Vector{Int}(undef, 2)

  @inbounds for ilay in 1:nlay
    @inbounds for icol in 1:ncol
      # index and factor for temperature interpolation
      ics.jtemp[icol,ilay] = fint((tlay[icol,ilay] - (ref.temp_min - ref.temp_delta)) / ref.temp_delta)
      ics.jtemp[icol,ilay] = min(ntemp - 1, max(1, ics.jtemp[icol,ilay])) # limit the index range
      ftemp[icol,ilay] = (tlay[icol,ilay] - ref.temp[ics.jtemp[icol,ilay]]) / ref.temp_delta

      # index and factor for pressure interpolation
      locpress = FT(1) + (log(play[icol,ilay]) - ref.press_log[1]) / ref.press_log_delta
      ics.jpress[icol,ilay] = min(npres-1, max(1, fint(locpress)))
      fpress[icol,ilay] = locpress - FT(ics.jpress[icol,ilay])

    end
  end
  # determine if in lower or upper part of atmosphere
  ics.tropo .= log.(play) .> ref.press_trop_log

  @inbounds for ilay in 1:nlay
    @inbounds for icol in 1:ncol
      # itropo = 1 lower atmosphere; itropo = 2 upper atmosphere
      itropo = fmerge(1,2,ics.tropo[icol,ilay])
      # loop over implemented combinations of major species
      @inbounds for iflav in 1:nflav
        igases .= flavor[:,iflav]
        @inbounds for itemp in 1:2
          # compute interpolation fractions needed for lower, then upper reference temperature level
          # compute binary species parameter (eta) for flavor and temperature and
          #  associated interpolation index and factors
          ratio_eta_half = ref.vmr[itropo,igases[1],(ics.jtemp[icol,ilay]+itemp-1)] /
                           ref.vmr[itropo,igases[2],(ics.jtemp[icol,ilay]+itemp-1)]
          col_mix[itemp,iflav,icol,ilay] = col_gas[icol,ilay,igases[1]] + ratio_eta_half * col_gas[icol,ilay,igases[2]]
          eta = fmerge(col_gas[icol,ilay,igases[1]] / col_mix[itemp,iflav,icol,ilay], FT(0.5),
                      col_mix[itemp,iflav,icol,ilay] > FT(2) * floatmin(FT))
          loceta = eta * FT(neta-1)
          ics.jeta[itemp,iflav,icol,ilay] = min(fint(loceta)+1, neta-1)
          feta = mod(loceta, 1)
          # compute interpolation fractions needed for minor species
          # ftemp_term = (FT(1)-ftemp(icol,ilay)) for itemp = 1, ftemp(icol,ilay) for itemp=2
          ftemp_term = (FT(2-itemp) + FT(2*itemp-3) * ftemp[icol,ilay])
          ics.fminor[1,itemp,iflav,icol,ilay] = (1-feta) * ftemp_term
          ics.fminor[2,itemp,iflav,icol,ilay] =        feta  * ftemp_term
          # compute interpolation fractions needed for major species
          ics.fmajor[1,1,itemp,iflav,icol,ilay] = (FT(1)-fpress[icol,ilay]) * ics.fminor[1,itemp,iflav,icol,ilay]
          ics.fmajor[2,1,itemp,iflav,icol,ilay] = (FT(1)-fpress[icol,ilay]) * ics.fminor[2,itemp,iflav,icol,ilay]
          ics.fmajor[1,2,itemp,iflav,icol,ilay] =        fpress[icol,ilay]  * ics.fminor[1,itemp,iflav,icol,ilay]
          ics.fmajor[2,2,itemp,iflav,icol,ilay] =        fpress[icol,ilay]  * ics.fminor[2,itemp,iflav,icol,ilay]
        end # reference temperatures
      end # iflav
    end # icol,ilay
  end
  return nothing

end

"""
    compute_tau_absorption!(...)

Compute minor and major species optical depth
from pre-computed interpolation coefficients (`ics`)

 - `lower` lower atmospheric variables
 - `upper` upper atmospheric variables
 - `lower_aux` lower atmospheric auxiliary variables
 - `upper_aux` upper atmospheric auxiliary variables
 - `ics` interpolation coefficients, see [`InterpolationCoefficients`](@ref)

# ---------------------
# input dimensions
integer,                                intent(in) :: ncol,nlay,nbnd,ngpt
integer,                                intent(in) :: ngas,nflav,neta,npres,ntemp
integer,                                intent(in) :: idx_h2o
# ---------------------
# inputs from object
integer,     dimension(2,ngpt),                  intent(in) :: gpoint_flavor
integer,     dimension(2,nbnd),                  intent(in) :: band_lims_gpt
real(FT),    dimension(ngpt,neta,npres+1,ntemp), intent(in) :: kmajor
# ---------------------
# inputs from profile or parent function
real(FT), dimension(2,    nflav,ncol,nlay       ), intent(in) :: col_mix
real(FT), dimension(            ncol,nlay       ), intent(in) :: play, tlay      # pressure and temperature
real(FT), dimension(            ncol,nlay,0:ngas), intent(in) :: col_gas
# ---------------------
# output - optical depth
real(FT), dimension(ngpt,nlay,ncol), intent(inout) :: tau
# ---------------------
# Local variables
#
logical                    :: top_at_1
integer, dimension(ncol,2) :: itropo_lower, itropo_upper
"""
function compute_tau_absorption!(tau,
              ncol,nlay,nbnd,ngpt,                  # dimensions
              idx_h2o,
              gpoint_flavor,
              band_lims_gpt,
              kmajor,
              lower,
              upper,
              lower_aux,
              upper_aux,
              ics::InterpolationCoefficients{FT},
              col_mix,
              play,
              tlay,
              col_gas) where {FT<:AbstractFloat}

  # ---------------------
  # Layer limits of upper, lower atmospheres
  # ---------------------
  top_at_1 = play[1,1] < play[1, nlay]
  itropo_lower = Array{Int}(undef, ncol, 2)
  itropo_upper = similar(itropo_lower)
  if top_at_1
    itropo_lower[:, 1] .= fminloc_wrapper(play, dim=2, mask=ics.tropo)
    itropo_lower[:, 2] .= nlay
    itropo_upper[:, 1] .= 1
    itropo_upper[:, 2] .= fmaxloc_wrapper(play, dim=2, mask=(.!ics.tropo)) # TODO:
  else
    itropo_lower[:, 1] .= 1
    itropo_lower[:, 2] .= fminloc_wrapper(play, dim=2, mask= ics.tropo)
    itropo_upper[:, 1] .= fmaxloc_wrapper(play, dim=2, mask=(.!ics.tropo))
    itropo_upper[:, 2] .= nlay
  end

  fill!(tau, FT(0))
  # ---------------------
  # Major Species
  # ---------------------

  gas_optical_depths_major!(
        ncol,nlay,nbnd,ngpt,
        gpoint_flavor,
        band_lims_gpt,
        kmajor,
        col_mix,
        ics,
        tau)
  # ---------------------
  # Minor Species - lower
  # ---------------------

  gas_optical_depths_minor!(
         ncol,
         ngpt,
         idx_h2o,
         gpoint_flavor[1,:],
         lower,
         lower_aux,
         play,
         tlay,
         col_gas,
         ics.fminor,
         ics.jeta,
         itropo_lower,
         ics.jtemp,
         tau,"1")
  # ---------------------
  # Minor Species - upper
  # ---------------------
  gas_optical_depths_minor!(
         ncol,
         ngpt,
         idx_h2o,
         gpoint_flavor[2,:],
         upper,
         upper_aux,
         play,
         tlay,
         col_gas,
         ics.fminor,
         ics.jeta,
         itropo_upper,
         ics.jtemp,
         tau,"2")
  return nothing
end


"""
    gas_optical_depths_major!(...)

compute minor species optical depths

 - `ics` interpolation coefficients, see [`InterpolationCoefficients`](@ref)

# input dimensions
integer, intent(in) :: ncol, nlay, nbnd, ngpt, nflav,neta,npres,ntemp  # dimensions

# inputs from object
integer,  dimension(2,ngpt),  intent(in) :: gpoint_flavor
integer,  dimension(2,nbnd),  intent(in) :: band_lims_gpt # start and end g-point for each band
real(FT), dimension(ngpt,neta,npres+1,ntemp), intent(in) :: kmajor

# inputs from profile or parent function
real(FT),    dimension(2,    nflav,ncol,nlay), intent(in) :: col_mix

# outputs
real(FT), dimension(ngpt,nlay,ncol), intent(inout) :: tau
# -----------------
# local variables
real(FT) :: tau_major(ngpt) # major species optical depth
# local index
integer :: icol, ilay, iflav, ibnd, igpt, itropo
integer :: gptS, gptE
"""
function gas_optical_depths_major!(ncol,nlay,nbnd,ngpt,
                                    gpoint_flavor, band_lims_gpt,    # inputs from object
                                    kmajor,
                                    col_mix,
                                    ics::InterpolationCoefficients{FT},
                                    tau::Array{FT}) where {FT<:AbstractFloat}

  tau_major = Array{FT}(undef, ngpt)
  for icol in 1:ncol
    for ilay in 1:nlay
      # itropo = 1 lower atmosphere; itropo = 2 upper atmosphere
      itropo = fmerge(1,2,ics.tropo[icol,ilay])
      # optical depth calculation for major species
      for ibnd in 1:nbnd
        gptS = band_lims_gpt[1, ibnd]
        gptE = band_lims_gpt[2, ibnd]
        iflav = gpoint_flavor[itropo, gptS] #eta interpolation depends on band's flavor
        tau_major[gptS:gptE] .=
          # interpolation in temperature, pressure, and eta
          interpolate3D_byflav(col_mix[:,iflav,icol,ilay],
                               ics.fmajor[:,:,:,iflav,icol,ilay],
                               kmajor,
                               band_lims_gpt[1, ibnd],
                               band_lims_gpt[2, ibnd],
                               ics.jeta[:,iflav,icol,ilay],
                               ics.jtemp[icol,ilay],
                               ics.jpress[icol,ilay]+itropo
                               )
        tau[gptS:gptE,ilay,icol] = tau[gptS:gptE,ilay,icol] .+ tau_major[gptS:gptE]
      end # igpt
    end
  end # ilay
  return nothing
end


"""
    gas_optical_depths_minor!(...)

compute minor species optical depths


integer,                                     intent(in   ) :: ncol,nlay,ngpt
integer,                                     intent(in   ) :: ngas,nflav
integer,                                     intent(in   ) :: ntemp,neta,nminor,nminork
integer,                                     intent(in   ) :: idx_h2o
integer,     dimension(ngpt),                intent(in   ) :: gpt_flv
real(FT),    dimension(nminork,neta,ntemp),  intent(in   ) :: kminor
integer,     dimension(2,nminor),            intent(in   ) :: minor_limits_gpt
logical(wl), dimension(  nminor),            intent(in   ) :: minor_scales_with_density
logical(wl), dimension(  nminor),            intent(in   ) :: scale_by_complement
integer,     dimension(  nminor),            intent(in   ) :: kminor_start
integer,     dimension(  nminor),            intent(in   ) :: idx_minor, idx_minor_scaling
real(FT),    dimension(ncol,nlay),           intent(in   ) :: play, tlay
real(FT),    dimension(ncol,nlay,0:ngas),    intent(in   ) :: col_gas
real(FT),    dimension(2,2,nflav,ncol,nlay), intent(in   ) :: fminor
integer,     dimension(2,  nflav,ncol,nlay), intent(in   ) :: jeta
integer,     dimension(ncol, 2),             intent(in   ) :: layer_limits
integer,     dimension(ncol,nlay),           intent(in   ) :: jtemp
real(FT),    dimension(ngpt,nlay,ncol),      intent(inout) :: tau
# -----------------
# local variables
real(FT), parameter :: PaTohPa = 0.01
real(FT) :: vmr_fact, dry_fact             # conversion from column abundance to dry vol. mixing ratio;
real(FT) :: scaling, kminor_loc            # minor species absorption coefficient, optical depth
integer  :: icol, ilay, iflav, igpt, imnr
integer  :: gptS, gptE
real(FT), dimension(ngpt) :: tau_minor

"""
function gas_optical_depths_minor!(ncol,
                                   ngpt,
                                   idx_h2o,
                                   gpt_flv,
                                   atmos,
                                   aux,
                                   play,
                                   tlay,
                                   col_gas,
                                   fminor,
                                   jeta,
                                   layer_limits,
                                   jtemp,
                                   tau,
                                   callername)

  # number of minor contributors, total num absorption coeffs
  nminork = size(atmos.kminor, 1)
  nminor  = size(atmos.minor_scales_with_density)
  #
  # Guard against layer limits being 0 -- that means don't do anything i.e. there are no
  #   layers with pressures in the upper or lower atmosphere respectively
  # First check skips the routine entirely if all columns are out of bounds...
  #
  FT = eltype(tau)

  tau_minor = Array{FT}(undef, ngpt)
  if any(layer_limits[:,1] .> 0)
    for imnr in 1:size(atmos.scale_by_complement,1) # loop over minor absorbers in each band
      for icol in 1:ncol
        #
        # This check skips individual columns with no pressures in range
        #
        if layer_limits[icol,1] > 0
          for ilay in layer_limits[icol,1]:layer_limits[icol,2]
            #
            # Scaling of minor gas absortion coefficient begins with column amount of minor gas
            #
            scaling = col_gas[icol,ilay,aux.idx_minor[imnr]]
            #
            # Density scaling (e.g. for h2o continuum, collision-induced absorption)
            #
            if atmos.minor_scales_with_density[imnr]
              #
              # NOTE: P needed in hPa to properly handle density scaling.
              #
              scaling = scaling * (PaTohPa(FT)*play[icol,ilay]/tlay[icol,ilay])
              if aux.idx_minor_scaling[imnr] > 0  # there is a second gas that affects this gas's absorption
                vmr_fact = FT(1) / col_gas[icol,ilay,0]
                dry_fact = FT(1) / (FT(1) + col_gas[icol,ilay,idx_h2o] * vmr_fact)
                # scale by density of special gas
                if atmos.scale_by_complement[imnr] # scale by densities of all gases but the special one
                  scaling = scaling * (FT(1) - col_gas[icol,ilay,aux.idx_minor_scaling[imnr]] * vmr_fact * dry_fact)
                else
                  scaling = scaling *          col_gas[icol,ilay,aux.idx_minor_scaling[imnr]] * vmr_fact * dry_fact
                end
              end
            end
            #
            # Interpolation of absorption coefficient and calculation of optical depth
            #
            # Which gpoint range does this minor gas affect?
            gptS = atmos.minor_limits_gpt[1,imnr]
            gptE = atmos.minor_limits_gpt[2,imnr]
            iflav = gpt_flv[gptS]
            jeta_tup = (jeta[1,iflav,icol,ilay],
                        jeta[2,iflav,icol,ilay])

            interpolate2D_byflav!(@view(tau_minor[gptS:gptE]),
                                  @view(fminor[:,:,iflav,icol,ilay]),
                                  atmos.kminor,
                                  gptS,
                                  atmos.kminor_start[imnr],
                                  atmos.kminor_start[imnr]+(gptE-gptS),
                                  jeta_tup,
                                  jtemp[icol,ilay])
            tau[gptS:gptE,ilay,icol] = tau[gptS:gptE,ilay,icol] + scaling*tau_minor[gptS:gptE]
          end
        end
      end
    end
  end
  return nothing
end

"""
    compute_tau_rayleigh!()

compute Rayleigh scattering optical depths

 - `ics` interpolation coefficients, see [`InterpolationCoefficients`](@ref)

integer,                                     intent(in ) :: ncol,nlay,nbnd,ngpt
integer,                                     intent(in ) :: ngas,nflav,neta,npres,ntemp
integer,     dimension(2,ngpt),              intent(in ) :: gpoint_flavor
integer,     dimension(2,nbnd),              intent(in ) :: band_lims_gpt # start and end g-point for each band
real(FT),    dimension(ngpt,neta,ntemp,2),   intent(in ) :: krayl
integer,                                     intent(in ) :: idx_h2o
real(FT),    dimension(ncol,nlay),           intent(in ) :: col_dry
real(FT),    dimension(ncol,nlay,0:ngas),    intent(in ) :: col_gas
# outputs
real(FT),    dimension(ngpt,nlay,ncol),      intent(out) :: tau_rayleigh
# -----------------
# local variables
real(FT) :: k(ngpt) # rayleigh scattering coefficient
integer  :: icol, ilay, iflav, ibnd, igpt, gptS, gptE
integer  :: itropo
# -----------------
"""
function compute_tau_rayleigh!(ncol::I,nlay::I,nbnd::I,ngpt::I,
                               gpoint_flavor::Array{I,2},
                               band_lims_gpt::Array{I,2},
                               krayl::Array{FT,4},
                               idx_h2o::I,
                               col_dry::Array{FT,2},
                               col_gas::AbstractArray{FT,3},
                               ics::InterpolationCoefficients{FT},
                               tau_rayleigh::Array{FT}) where {FT<:AbstractFloat, I<:Integer, B<:Bool}
  k = Array{FT}(undef, ngpt)
  @inbounds for ilay in 1:nlay
    @inbounds for icol in 1:ncol
      itropo = fmerge(1,2,ics.tropo[icol,ilay]) # itropo = 1 lower atmosphere; itropo = 2 upper atmosphere
      @inbounds for ibnd in 1:nbnd
        gptS = band_lims_gpt[1, ibnd]
        gptE = band_lims_gpt[2, ibnd]
        iflav = gpoint_flavor[itropo, gptS] #eta interpolation depends on band's flavor

        fminor_tup = (ics.fminor[1,1,iflav,icol,ilay],
                      ics.fminor[2,1,iflav,icol,ilay],
                      ics.fminor[1,2,iflav,icol,ilay],
                      ics.fminor[2,2,iflav,icol,ilay])
        jeta_tup = (ics.jeta[1,iflav,icol,ilay],
                    ics.jeta[2,iflav,icol,ilay])
        interpolate2D_byflav!(@view(k[gptS:gptE]),
                              fminor_tup,
                              @view(krayl[:,:,:,itropo]),
                              gptS,
                              gptS,
                              gptE,
                              jeta_tup,
                              ics.jtemp[icol,ilay])

        tau_rayleigh[gptS:gptE,ilay,icol] .= k[gptS:gptE] .*
                                            (col_gas[icol,ilay,idx_h2o]+col_dry[icol,ilay])
      end
    end
  end
  return nothing
end

"""
    compute_Planck_source!(...)

 - `ics` interpolation coefficients, see [`InterpolationCoefficients`](@ref)

integer,                                    intent(in) :: ncol, nlay, nbnd, ngpt
integer,                                    intent(in) :: nflav, neta, npres, ntemp, nPlanckTemp
real(FT),    dimension(ncol,nlay  ),        intent(in) :: tlay
real(FT),    dimension(ncol,nlay+1),        intent(in) :: tlev
real(FT),    dimension(ncol       ),        intent(in) :: tsfc
integer,                                    intent(in) :: sfc_lay
# Table-specific
integer, dimension(ngpt),                     intent(in) :: gpoint_bands # start and end g-point for each band
integer, dimension(2, nbnd),                  intent(in) :: band_lims_gpt # start and end g-point for each band
real(FT),                                     intent(in) :: temp_ref_min, totplnk_delta
real(FT), dimension(ngpt,neta,npres+1,ntemp), intent(in) :: pfracin
real(FT), dimension(nPlanckTemp,nbnd),        intent(in) :: totplnk
integer,  dimension(2,ngpt),                  intent(in) :: gpoint_flavor

real(FT), dimension(ngpt,     ncol), intent(out) :: sfc_src
real(FT), dimension(ngpt,nlay,ncol), intent(out) :: lay_src
real(FT), dimension(ngpt,nlay,ncol), intent(out) :: lev_src_inc, lev_src_dec
# -----------------
# local
integer  :: ilay, icol, igpt, ibnd, itropo, iflav
integer  :: gptS, gptE
real(FT), dimension(2), parameter :: one = [1._wp, 1._wp]
real(FT) :: pfrac          (ngpt,nlay,  ncol)
real(FT) :: planck_function(nbnd,nlay+1,ncol)
# -----------------
"""
function compute_Planck_source!(
                  ncol, nlay, nbnd, ngpt,
                  nflav, neta, npres, ntemp, nPlanckTemp,
                  tlay, tlev, tsfc, sfc_lay,
                  ics::InterpolationCoefficients{FT},
                  gpoint_bands, band_lims_gpt,
                  pfracin, temp_ref_min, totplnk_delta, totplnk, gpoint_flavor,
                  sfc_src, lay_src, lev_src_inc, lev_src_dec) where FT

  pfrac = Array{FT}(undef,ngpt,nlay,ncol)
  pfrac .= 0.0

  planck_function = Array{FT}(undef,nbnd,nlay+1,ncol)
  planck_function .= 0.0

  # Calculation of fraction of band's Planck irradiance associated with each g-point
  for icol in 1:ncol
    for ilay in 1:nlay
      # itropo = 1 lower atmosphere; itropo = 2 upper atmosphere
      itropo = fmerge(1,2,ics.tropo[icol,ilay])
      for ibnd = 1:nbnd
        gptS = band_lims_gpt[1, ibnd]
        gptE = band_lims_gpt[2, ibnd]
        iflav = gpoint_flavor[itropo, gptS] #eta interpolation depends on band's flavor
          # interpolation in temperature, pressure, and eta
        pfrac[gptS:gptE,ilay,icol] =
          interpolate3D_byflav(FT[1,1],
                               ics.fmajor[:,:,:,iflav,icol,ilay],
                               pfracin,
                               band_lims_gpt[1, ibnd],
                               band_lims_gpt[2, ibnd],
                               ics.jeta[:,iflav,icol,ilay],
                               ics.jtemp[icol,ilay],
                               ics.jpress[icol,ilay]+itropo)
      end # band
    end   # layer
  end     # column

  #
  # Planck function by band for the surface
  # Compute surface source irradiance for g-point, equals band irradiance x fraction for g-point
  #
  for icol in 1:ncol
    planck_function[1:nbnd,1,icol] = interpolate1D(tsfc[icol], temp_ref_min, totplnk_delta, totplnk)
    #
    # Map to g-points
    #
    for ibnd in 1:nbnd
      gptS = band_lims_gpt[1, ibnd]
      gptE = band_lims_gpt[2, ibnd]
      for igpt in gptS:gptE
        sfc_src[igpt, icol] = pfrac[igpt,sfc_lay,icol] * planck_function[ibnd, 1, icol]
      end
    end
  end # icol

  for icol in 1:ncol
    for ilay in 1:nlay
      # Compute layer source irradiance for g-point, equals band irradiance x fraction for g-point
      planck_function[1:nbnd,ilay,icol] = interpolate1D(tlay[icol,ilay], temp_ref_min, totplnk_delta, totplnk)
      #
      # Map to g-points
      #
      for ibnd in 1:nbnd
        gptS = band_lims_gpt[1, ibnd]
        gptE = band_lims_gpt[2, ibnd]
        for igpt in gptS:gptE
          lay_src[igpt,ilay,icol] = pfrac[igpt,ilay,icol] * planck_function[ibnd,ilay,icol]
        end
      end
    end # ilay
  end # icol

  # compute level source irradiances for each g-point, one each for upward and downward paths
  for icol in 1:ncol
    planck_function[1:nbnd,       1,icol] = interpolate1D(tlev[icol,     1], temp_ref_min, totplnk_delta, totplnk)
    for ilay in 1:nlay
      planck_function[1:nbnd,ilay+1,icol] = interpolate1D(tlev[icol,ilay+1], temp_ref_min, totplnk_delta, totplnk)
      #
      # Map to g-points
      #
      for ibnd in 1:nbnd
        gptS = band_lims_gpt[1, ibnd]
        gptE = band_lims_gpt[2, ibnd]
        for igpt in gptS:gptE
          lev_src_inc[igpt,ilay,icol] = pfrac[igpt,ilay,icol] * planck_function[ibnd,ilay+1,icol]
          lev_src_dec[igpt,ilay,icol] = pfrac[igpt,ilay,icol] * planck_function[ibnd,ilay,  icol]
        end
      end
    end # ilay
  end # icol
  return nothing

end

"""
    interpolate1D(...)

One dimensional interpolation -- return all values along second table dimension


# input
real(FT), intent(in) :: val,     # axis value at which to evaluate table
                        offset,  # minimum of table axis
                        delta     # step size of table axis
real(FT), dimension(:,:),
          intent(in) :: table # dimensions (axis, values)
# output
real(FT), dimension(size(table,dim=2)) :: res

# local
real(FT) :: val0 # fraction index adjusted by offset and delta
integer :: index # index term
real(FT) :: frac # fractional term
# -------------------------------------
"""
function interpolate1D(val, offset, delta, table)
  FT = eltype(delta)
  res = Vector{FT}(undef, size(table, 2))
  val0 = (val - offset) / delta
  frac = val0 - fint(val0) # get fractional part
  index = Integer(min(size(table,1)-1, max(1, fint(val0)+1))) # limit the index range
  res .= table[index,:] + frac * (table[index+1,:] - table[index,:])
  return res
end

"""
    interpolate2D(...)

This function returns a single value from a subset (in gpoint) of the k table

real(FT), dimension(2,2), intent(in) :: fminor # interpolation fractions for minor species
                                   # index(1) : reference eta level (temperature dependent)
                                   # index(2) : reference temperature level
real(FT), dimension(:,:,:), intent(in) :: k # (g-point, eta, temp)
integer,                    intent(in) :: igpt, jtemp # interpolation index for temperature
integer, dimension(2),      intent(in) :: jeta # interpolation index for binary species parameter (eta)
real(FT)                             :: res # the result
"""
function interpolate2D(fminor, k, igpt, jeta, jtemp)
  res =
    fminor[1,1] * k[igpt, jeta[1]  , jtemp  ] +
    fminor[2,1] * k[igpt, jeta[1]+1, jtemp  ] +
    fminor[1,2] * k[igpt, jeta[2]  , jtemp+1] +
    fminor[2,2] * k[igpt, jeta[2]+1, jtemp+1]
  return res
end

"""
    interpolate2D_byflav(...)

This function returns a range of values from a subset (in gpoint) of the k table

real(FT), dimension(2,2), intent(in) :: fminor # interpolation fractions for minor species
                                   # index(1) : reference eta level (temperature dependent)
                                   # index(2) : reference temperature level
real(FT), dimension(:,:,:), intent(in) :: k # (g-point, eta, temp)
integer,                    intent(in) :: gptS, gptE, jtemp # interpolation index for temperature
integer, dimension(2),      intent(in) :: jeta # interpolation index for binary species parameter (eta)
real(FT), dimension(gptE-gptS+1)       :: res # the result

# Local variable
integer :: igpt
"""
function interpolate2D_byflav!(res::AbstractArray{FT,1},
                               fminor,
                               k::AbstractArray{FT,3},
                               resS::I,
                               gptS::I,
                               gptE::I,
                               jeta,
                               jtemp::I) where {FT<:AbstractFloat,I<:Int}
  # each code block is for a different reference temperature
  for igpt in 1:gptE-gptS+1
    i_gpt = gptS+igpt-1
    res[igpt] = fminor[1] * k[i_gpt, jeta[1]  , jtemp  ] +
                fminor[2] * k[i_gpt, jeta[1]+1, jtemp  ] +
                fminor[3] * k[i_gpt, jeta[2]  , jtemp+1] +
                fminor[4] * k[i_gpt, jeta[2]+1, jtemp+1]
  end
  return nothing
end

"""
    interpolate3D(...)

interpolation in temperature, pressure, and eta

real(FT), dimension(2),     intent(in) :: scaling
real(FT), dimension(2,2,2), intent(in) :: fmajor # interpolation fractions for major species
                                                 # index(1) : reference eta level (temperature dependent)
                                                 # index(2) : reference pressure level
                                                 # index(3) : reference temperature level
real(FT), dimension(:,:,:,:),intent(in) :: k # (gpt, eta,temp,press)
integer,                     intent(in) :: igpt
integer, dimension(2),       intent(in) :: jeta # interpolation index for binary species parameter (eta)
integer,                     intent(in) :: jtemp # interpolation index for temperature
integer,                     intent(in) :: jpress # interpolation index for pressure
real(FT)                                :: res # the result
"""
function interpolate3D(scaling, fmajor, k, igpt, jeta, jtemp, jpress)
  # each code block is for a different reference temperature
  res =
    scaling[1] *
    ( fmajor[1,1,1] * k[igpt, jeta[1]  , jpress-1, jtemp  ] +
      fmajor[2,1,1] * k[igpt, jeta[1]+1, jpress-1, jtemp  ] +
      fmajor[1,2,1] * k[igpt, jeta[1]  , jpress  , jtemp  ] +
      fmajor[2,2,1] * k[igpt, jeta[1]+1, jpress  , jtemp  ] ) +
    scaling[2] *
    ( fmajor[1,1,2] * k[igpt, jeta[2]  , jpress-1, jtemp+1] +
      fmajor[2,1,2] * k[igpt, jeta[2]+1, jpress-1, jtemp+1] +
      fmajor[1,2,2] * k[igpt, jeta[2]  , jpress  , jtemp+1] +
      fmajor[2,2,2] * k[igpt, jeta[2]+1, jpress  , jtemp+1] )
  return res
end

"""
    interpolate3D_byflav(...)

real(FT), dimension(2),     intent(in) :: scaling
real(FT), dimension(2,2,2), intent(in) :: fmajor # interpolation fractions for major species
                                                 # index(1) : reference eta level (temperature dependent)
                                                 # index(2) : reference pressure level
                                                 # index(3) : reference temperature level
real(FT), dimension(:,:,:,:),intent(in) :: k # (gpt, eta,temp,press)
integer,                     intent(in) :: gptS, gptE
integer, dimension(2),       intent(in) :: jeta # interpolation index for binary species parameter (eta)
integer,                     intent(in) :: jtemp # interpolation index for temperature
integer,                     intent(in) :: jpress # interpolation index for pressure
real(FT), dimension(gptE-gptS+1)        :: res # the result

# Local variable
integer :: igpt
"""
function interpolate3D_byflav(scaling, fmajor, k, gptS, gptE, jeta, jtemp, jpress)
  # each code block is for a different reference temperature
  FT = eltype(k)
  res = Vector{FT}(undef, gptE-gptS+1)
  for igpt = 1:gptE-gptS+1
    res[igpt] =
      scaling[1] *
      ( fmajor[1,1,1] * k[gptS+igpt-1, jeta[1]  , jpress-1, jtemp  ] +
        fmajor[2,1,1] * k[gptS+igpt-1, jeta[1]+1, jpress-1, jtemp  ] +
        fmajor[1,2,1] * k[gptS+igpt-1, jeta[1]  , jpress  , jtemp  ] +
        fmajor[2,2,1] * k[gptS+igpt-1, jeta[1]+1, jpress  , jtemp  ] ) +
      scaling[2] *
      ( fmajor[1,1,2] * k[gptS+igpt-1, jeta[2]  , jpress-1, jtemp+1] +
        fmajor[2,1,2] * k[gptS+igpt-1, jeta[2]+1, jpress-1, jtemp+1] +
        fmajor[1,2,2] * k[gptS+igpt-1, jeta[2]  , jpress  , jtemp+1] +
        fmajor[2,2,2] * k[gptS+igpt-1, jeta[2]+1, jpress  , jtemp+1] )
  end
  return res
end

"""
    combine_and_reorder_2str!(...)

Combine absoprtion and Rayleigh optical depths for total tau, ssa, g

integer,                             intent(in) :: ncol, nlay, ngpt
real(FT), dimension(ngpt,nlay,ncol), intent(in   ) :: tau_abs, tau_rayleigh
real(FT), dimension(ncol,nlay,ngpt), intent(inout) :: tau, ssa, g # inout because components are allocated
"""
function combine_and_reorder_2str!(op::AbstractOpticalProps{FT}, ncol, nlay, ngpt, tau_abs, tau_rayleigh) where FT
  for icol in 1:ncol
    for ilay in 1:nlay
      for igpt in 1:ngpt
         t = tau_abs[igpt,ilay,icol] + tau_rayleigh[igpt,ilay,icol]
         op.tau[icol,ilay,igpt] = t
         op.g[icol,ilay,igpt] = FT(0)
         if (t > FT(2) * floatmin(FT))
           op.ssa[icol,ilay,igpt] = tau_rayleigh[igpt,ilay,icol] / t
         else
           op.ssa[icol,ilay,igpt] = FT(0)
         end
      end
    end
  end
  return nothing
end