using Test
include("main.jl")
using CSV, DataFrames
global saveplot = true
const PLOTDIR = raw"C:\codestuff\PBS\plots_one_64"
isdir(PLOTDIR) || mkpath(PLOTDIR)
pc(s)=(s=replace(s,r"[\{\}]"=>"");o=Tuple{Int,Int}[];for c in strip.(split(s,">")); c=replace(c,"<"=>"");p=split(strip(c));length(p)==2&&push!(o,(parse(Int,p[1])+1,parse(Int,p[2])+1));end;o)
rot(c,Ly)=(Ly+1-c[2],c[1])
df=CSV.read(raw"C:\codestuff\PBS\HeGithub\Large_scale_RL_10_61_21_61_formatted.csv",DataFrame);rename!(df,strip.(names(df)))
r=first(filter(x->string(x[:id])=="10x61_61_21_64",eachrow(df)))
Lx_s,Ly_s=parse.(Int,split(r[Symbol("Lx x Ly")],'x'))
io=pc(r[:IOs]);esc=pc(r[:Escorts]);itm=pc(r[Symbol("Target Loads")])
allc=vcat(io,esc,itm);Lx=max(Lx_s,maximum(c[1] for c in allc));Ly=max(Ly_s,maximum(c[2] for c in allc))
if any(c->c[2]>1,io); io=[rot(c,Ly) for c in io];esc=[rot(c,Ly) for c in esc];itm=[rot(c,Ly) for c in itm];Lx,Ly=Ly,Lx; end
IOc = length(io)==1 ? io[1] : io
escorts=Dict{String,escort}();for (k,c) in enumerate(esc);escorts["E$k"]=escort("E$k",c,String[],String[],0,Dict{Int64,Vector{String}}(),Tuple{Int64,Int64}[]);end
items=Dict{String,item}();for (k,c) in enumerate(itm);items["I$k"]=item("I$k",c,0,0,1000.0,1,nothing);end
st=fill("0",Lx,Ly);for (k,e) in escorts;st[e.coords...]=k;end;for (k,it) in items;st[it.coords...]=k;end
FREEROAM_GRADIENT[]=false
println("grid $(Lx)x$(Ly)  #IOs=$(length(io))  #esc=$(length(esc))  #loads=$(length(itm))")
_,_,ms = main(st,items,escorts,IOc,"64",PLOTDIR; n=length(items),no_cores=1,mode="continue",mm="lm",iter_cap=250)
println("RESULT: makespan(iters)=$ms   escort_relocs=$(ESCORT_RELOCS[])   (cap was 250)")
