# This file assumes that the directories are organized as follows:
#
# ./SomeDirectory/JRRTMGP
# ./SomeDirectory/rte-rrtmgp
#

get_VPATH(root_dir) = filter(i->!occursin(".git",i), [joinpath(root, dir) for (root, dirs, files) in walkdir(root_dir) for dir in dirs])

if Sys.iswindows()
  # ENV["NCHOME"] = joinpath("C:","Program Files","netCDF 4.7.1","bin")
  # ENV["NCHOME"] = joinpath("C:","Program Files","netCDF 4.7.1","lib")
  ENV["NCHOME"] = joinpath("C:","Program Files","netCDF 4.7.1")
  # ENV["NFHOME"] = joinpath("C:","MinGW","bin")
  ENV["NFHOME"] = joinpath("C:","MinGW")
else
# ENV["NCHOME"] = "/usr/local/Cellar/netcdf/4.6.1_4"
  ENV["NCHOME"] = "/usr/local"
  ENV["NFHOME"] = "/usr/local"
  # ENV["NCHOME"] = joinpath("/usr","local","Cellar","netcdf","4.6.1_4")
  # ENV["NFHOME"] = joinpath("/usr","local","Cellar","netcdf","4.6.1_4")
end

root_dir = dirname(pwd())
rte_rrtmgp_dir = joinpath(root_dir,"rte-rrtmgp")
rte_rrtmgp_test_val_dir = joinpath(root_dir,"rte-rrtmgp-test-val")

# rte-rrtmgp ENV variables
ENV["RTE_KERNELS"] = joinpath(rte_rrtmgp_dir,"rte","kernels")

# rte-rrtmgp and rte-rrtmgp-test-val ENV variables
ENV["RTE_DIR"] = joinpath(rte_rrtmgp_dir,"rte")
ENV["RTE_KERNEL_DIR"] = joinpath(rte_rrtmgp_dir,"rte","kernels")
ENV["RRTMGP_KERNEL_DIR"] = joinpath(rte_rrtmgp_dir,"rrtmgp","kernels")
ENV["RRTMGP_DIR"] = joinpath(rte_rrtmgp_dir,"build")
ENV["FCFLAGS"]="-fimplicit-none -ffree-line-length-none -Wuninitialized -cpp -std=gnu"
ENV["FC"] = "gfortran"

# rte-rrtmgp-test-val ENV variables
ENV["TEST_ROOT"] = rte_rrtmgp_test_val_dir
ENV["RRTMGP_ROOT"] = rte_rrtmgp_dir
ENV["RRTMGP_BUILD"] = joinpath(rte_rrtmgp_dir,"build")

# ENV["VPATH_DIR"] = join(get_VPATH(rte_rrtmgp_dir), " ")

cd(joinpath(root_dir,"rte-rrtmgp","build")) do
  rm("Makefile.libs"; force=true)
  rm("Makefile.conf"; force=true)
  rm("Makefile.rules"; force=true)
end

cd(joinpath(root_dir,"rte-rrtmgp","build")) do
  run(`make clean`)
  run(`make`)
end

cd(joinpath(root_dir,"rte-rrtmgp","examples","rfmip-clear-sky")) do
  rm("generate-output-file-templates.py"; force=true)
  rm("multiple_input4MIPs_radiation_RFMIP_UColorado-RFMIP-1-2_none.nc"; force=true)
  rm("rld_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc"; force=true)
  rm("rlu_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc"; force=true)
  rm("rrtmgp_rfmip_lw"; force=true)
  rm("rrtmgp_rfmip_sw"; force=true)
  rm("rsd_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc"; force=true)
  rm("rsu_Efx_RTE-RRTMGP-181204_rad-irf_r1i1p1f1_gn.nc"; force=true)

  run(`make clean`)
  run(`make`)
  # stage_files.py calls urllib.request.urlretrieve, so call sparingly (can get blocked out by too many calls)
  run(`python stage_files.py`)
  run(`python run-rfmip-examples.py`)
end
