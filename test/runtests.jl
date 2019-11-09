using Test
ENV["DATADEPS_ALWAYS_ACCEPT"] = true

# include("AutoRunRRTMGP.jl")
for submodule in [
                  "DataDeps",
                  "rfmip_clear_sky_sw",
                  "rfmip_clear_sky_lw",
                  "allsky",
                  ]

  println("Testing $submodule")
  include(joinpath(submodule*".jl"))
end