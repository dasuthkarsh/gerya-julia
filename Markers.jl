#
#
#     DEFINITIONS OF MARKERS AND ROUTINES FOR LOCATING THEM
#
#

mutable struct Markers    
    x::Array{Float64,2}
    cell::Array{Int64,2}
    scalarFields::Dict
    scalars::Array{Float64,2}
    integerFields::Dict
    integers::Array{Int16,2} # note - this could be changed if larger numbers need to be stored...

    nmark::Int64
    
    function Markers(grid::CartesianGrid,scalarFieldNames,integerFieldNames; nmx::Integer=5,nmy::Integer=5,random::Bool=false)
        N = nmx*nmy*(grid.nx-1)*(grid.ny-1) # total number of markers
        mdx = grid.W/nmx/(grid.nx-1)
        mdy = grid.H/nmy/(grid.ny-1)
        
        n_fields = length(scalarFieldNames)
        scalarFields = Dict()
        ind=1
        for field in scalarFieldNames
           scalarFields[field] = ind
           ind += 1
        end
        
        n_ifields = length(integerFieldNames)
        integerFields = Dict()
        ind=1
        for field in integerFieldNames
            integerFields[field] = ind
            ind += 1
        end
        
        x = Array{Float64,2}(undef,2,N)
        cell = Array{Int64,2}(undef,2,N)
        
        scalars = Array{Float64,2}(undef,n_fields,N)
        integers = Array{Int16,2}(undef,n_ifields,N)
        
        k=1
        for i in 1:(grid.ny-1)
            for j in 1:(grid.nx-1)
                for ii in 1:nmy
                     for jj in 1:nmx
                        x[1,k] = mdx/2. + mdx*(jj-1) + mdx*nmx*(j-1) + ( random ? (rand()-0.5)*mdx : 0.0 )
                        x[2,k] = mdy/2. + mdy*(ii-1) + mdy*nmy*(i-1) + ( random ? (rand()-0.5)*mdy : 0.0 )
                        cell[1,k] = j
                        cell[2,k] = i
                        k+=1
                    end
                end
            end
        end

        new(x,cell,scalarFields,scalars,integerFields,integers,k-1)
    end
end

function find_cell(x::Float64,gridx::Vector{Float64},nx::Int64 ; guess::Int64=nothing)
    # find the cell in the array gridx that contains the current marker
    # first, see whether the initial guess is correct.
    lower::Int64 = 1
    upper::Int64 = nx
    if guess != nothing && guess >= 1 && guess < nx
        if x >= gridx[guess] && x < gridx[guess+1]
            return guess            
        elseif guess < nx-1 && x>=gridx[guess+1] && x<gridx[guess+2]
            return guess+1
        elseif guess > 1 && x < gridx[guess] && x >= gridx[guess-1]
            return guess-1
        else
            if x>=gridx[guess+1]
                lower = guess
            else
                upper = guess+1
            end
        end
     end
    # locate cell using bisection on lower,upper
    while upper-lower > 1 
        midpoint::Int = lower + floor((upper-lower)/2)
        if x >= gridx[midpoint]
            lower = midpoint
        else
            upper = midpoint
        end
    end
    return lower
end

function find_cells!(markers::Markers,grid::CartesianGrid)
   for i in 1:markers.nmark
        markers.cell[1,i] = find_cell(markers.x[1,i] , grid.x, grid.nx, guess=markers.cell[1,i])
        markers.cell[2,i] = find_cell(markers.x[2,i] , grid.y, grid.ny, guess=markers.cell[2,i])
    end
end


#
#
#     ROUTINES RELATED TO MARKERS -> NODES
#
#
function marker_to_basic_node(m::Markers,grid::CartesianGrid,fieldnames::Vector{String})
    # move quantities from the markers to the basic nodes.
    # This is a convenience function that allows the field names to be passed as a list of strings.
    # m should be the Markers (see Markers.jl)
    # grid should be the Cartesian grid
    # fieldnames is a vector of strings such as ["rho","T"] that correspond to fields defined on the markers
    #
    nfields = length(fieldnames)
    # markerfields will be indices into the 'scalars' array
    markerfields = [m.scalarFields[tmp] for tmp in fieldnames]
    
    return marker_to_basic_node(m,grid, m.scalars[markerfields,:] )
end

function marker_to_basic_node(m::Markers,grid::CartesianGrid,markerfield::Array{Float64,2})
     # move quantities from the markers to the basic nodes.
     # currently moves rho and eta.
     # returns rho, eta, each as a ny-by-nx matrix
     nfield = size(markerfield,1);

     weights = zeros(Float64,grid.ny,grid.nx)
     field = zeros(Float64,grid.ny,grid.nx,nfield)
     # loop over the markers
     for i in 1:m.nmark
        # calculate weights for four surrounding basic nodes
          cellx::Int64 = m.cell[1,i]
          celly::Int64 = m.cell[2,i]
          wx = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
          wy = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
          #i,j
          wt_i_j=(1.0-wx)*(1.0-wy)
          #i+1,j        
          wt_i1_j = (1.0-wx)*(wy)
          #i,j+1
          wt_i_j1 = (wx)*(1.0-wy)
          #i+1,j+1
          wt_i1_j1 = (wx)*(wy)

          for k in 1:nfield
              field[celly,cellx,k] += wt_i_j*markerfield[k,i]
              field[celly+1,cellx,k] += wt_i1_j*markerfield[k,i]
              field[celly,cellx+1,k] += wt_i_j1*markerfield[k,i]
              field[celly+1,cellx+1,k] += wt_i1_j1*markerfield[k,i]
          end
          weights[celly,cellx] += wt_i_j
          weights[celly+1,cellx] += wt_i1_j
          weights[celly,cellx+1] += wt_i_j1
          weights[celly+1,cellx+1] += wt_i1_j1       
     end
    
     return [field[:,:,k]./weights for k in 1:nfield]
 end


function marker_to_cell_center(m::Markers,grid::CartesianGrid,fieldnames::Vector{String})
    # move a list of fields (given as a list of strings in fieldnames) from markers to cell centers.
    nfields = length(fieldnames)
    # markerfields will be indices into the 'scalars' array
    markerfields = [m.scalarFields[tmp] for tmp in fieldnames]
    return marker_to_cell_center(m,grid,m.scalars[markerfields,:])
end

function marker_to_cell_center(m::Markers,grid::CartesianGrid,markerfield::Array{Float64,2})
    # markerfields will be indices into the 'scalars' array

    # loop over the markers    
    nfield = size(markerfield,1);

    weights = zeros(Float64,grid.ny+1,grid.nx+1)
    field = zeros(Float64,grid.ny+1,grid.nx+1,nfield)
    
    for i in 1:m.nmark
       # calculate weights for four surrounding cell centers
         cellx::Int64 =  m.cell[1,i]
         cellx += cellx < grid.nx && m.x[1,i] >= grid.xc[cellx+1] ? 1 : 0
         celly::Int64 = m.cell[2,i]
         celly += celly < grid.ny && m.x[2,i] >= grid.yc[celly+1] ? 1 : 0
        
         wx = (m.x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx]) # mdx/dx
         wy = (m.x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
         #i,j
         wt_i_j=(1.0-wx)*(1.0-wy)
         #i+1,j        
         wt_i1_j = (1.0-wx)*(wy)
         #i,j+1
         wt_i_j1 = (wx)*(1.0-wy)
         #i+1,j+1
         wt_i1_j1 = (wx)*(wy)
        
         for k in 1:nfield
             field[celly,cellx,k] += wt_i_j*markerfield[k,i]
             field[celly+1,cellx,k] += wt_i1_j*markerfield[k,i]
             field[celly,cellx+1,k] += wt_i_j1*markerfield[k,i]
             field[celly+1,cellx+1,k] += wt_i1_j1*markerfield[k,i]
        end
         weights[celly,cellx] += wt_i_j
         weights[celly+1,cellx] += wt_i1_j
         weights[celly,cellx+1] += wt_i_j1
         weights[celly+1,cellx+1] += wt_i1_j1       
    end

    return [field[:,:,k]./weights for k in 1:nfield]
end


function marker_to_stag(m::Markers,grid::CartesianGrid,fieldnames::Vector{String},node_type::String)
    # node type can be "basic","vx", "vy", or "center"
    stagx::Int64 = 0 
    stagy::Int64 = 0
    if node_type == "basic"
        stagx=0
        stagy=0
    elseif node_type == "vx"
        stagx = 0
        stagy = -1
    elseif node_type == "vy"
        stagx = -1
        stagy = 0
    elseif node_type == "center"
        stagx = -1
        stagy = -1
    else
        error("node type unknown")
    end
    
    # move a list of fields (given as a list of strings in fieldnames) from markers to cell centers.
    nfields = length(fieldnames)
    # markerfields will be indices into the 'scalars' array
    markerfields = [m.scalarFields[tmp] for tmp in fieldnames]
    return marker_to_stag(m,grid,m.scalars[markerfields,:],stagx,stagy)
end

function marker_to_stag(m::Markers,grid::CartesianGrid,markerfield::Array{Float64,2},stagx::Int64,stagy::Int64)
    # markerfields will be indices into the 'scalars' array
    # If stagx and stagy are zero, this function performs the same task as markers to basic nodes
    # if stagx=-1 and stagy=-1, this function performs interpolation to cell centers.
    #assert(stagx == -1 || stagx == 0)
    #assert(stagy == -1 || stagy == 0)

    # loop over the markers    
    nfield = size(markerfield,1)
    NX::Int64 = grid.nx
    if stagx == -1 # if the grid is staggered in the x direction, pad out by one cell to include ghost nodes outside right
        NX += 1
    end
    NY::Int64 = grid.ny
    if stagy == -1 # if the grid is staggered in the y direction, pad out by one cell to include ghost nodes outside below
        NY += 1
    end
    
    weights = zeros(Float64,NY,NX)
    field = zeros(Float64,NY,NX,nfield)
    
    for i in 1:m.nmark
       # calculate weights for four surrounding cell centers
         cellx::Int64 =  m.cell[1,i]
         if stagx == -1
             cellx += cellx < grid.nx && m.x[1,i] >= grid.xc[cellx+1] ? 1 : 0
         end
         celly::Int64 = m.cell[2,i]
         if stagy == -1
             celly += celly < grid.ny && m.x[2,i] >= grid.yc[celly+1] ? 1 : 0
         end
         if stagx == -1
             wx = (m.x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx]) # mdx/dx
         else 
            wx = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
         end
         if stagy == -1
            wy = (m.x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
         else
            wy = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
         end
         #i,j
         wt_i_j=(1.0-wx)*(1.0-wy)
         #i+1,j        
         wt_i1_j = (1.0-wx)*(wy)
         #i,j+1
         wt_i_j1 = (wx)*(1.0-wy)
         #i+1,j+1
         wt_i1_j1 = (wx)*(wy)
        
         for k in 1:nfield
             field[celly,cellx,k] += wt_i_j*markerfield[k,i]
             field[celly+1,cellx,k] += wt_i1_j*markerfield[k,i]
             field[celly,cellx+1,k] += wt_i_j1*markerfield[k,i]
             field[celly+1,cellx+1,k] += wt_i1_j1*markerfield[k,i]
        end
         weights[celly,cellx] += wt_i_j
         weights[celly+1,cellx] += wt_i1_j
         weights[celly,cellx+1] += wt_i_j1
         weights[celly+1,cellx+1] += wt_i1_j1       
    end

    return [field[:,:,k]./weights for k in 1:nfield]
end

#
#
#     ROUTINES RELATED TO NODES -> MARKER
#
#

function basic_node_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix{Float64},mfield::String)
    k = m.scalarFields[mfield]
    Threads.@threads for i in 1:m.nmark
        cellx = m.cell[1,i]
        celly = m.cell[2,i]
        wx::Float64 = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
        wy::Float64 = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
        
        m.scalars[k,i] = (1.0-wx)*(1.0-wy)*field[celly,cellx] +
            + (wx)*(1.0-wy)*field[celly,cellx+1] +
            + (1.0-wx)*(wy)*field[celly+1,cellx] +
            + (wx)*(wy)*field[celly+1,cellx+1]
    end
end

function basic_node_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix{Float64},mfield::Array{Float64,1})
    Threads.@threads for i in 1:m.nmark
        cellx = m.cell[1,i]
        celly = m.cell[2,i]
        wx::Float64 = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
        wy::Float64 = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
        
        mfield[i] = (1.0-wx)*(1.0-wy)*field[celly,cellx] +
            + (wx)*(1.0-wy)*field[celly,cellx+1] +
            + (1.0-wx)*(wy)*field[celly+1,cellx] +
            + (wx)*(wy)*field[celly+1,cellx+1]
    end
end

function cell_center_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix{Float64},mfield::Array{Float64,2})
    if size(field,1) == grid.nx+1
        cellx_max = grid.nx
    else
        cellx_max = grid.nx-1
    end
    if size(field,2) == grid.ny+1
        celly_max = grid.ny
    else
        celly_max = grid.ny-1
    end
    
    Threads.@threads for i in 1:m.nmark
        local cellx::Int64 = m.cell[1,i]
        local celly::Int64 = m.cell[2,i]
        
        cellx += cellx < cellx_max && m.x[1,i] >= grid.xc[cellx+1] ? 1 : 0
        celly = m.cell[2,i]
        celly += celly < celly_max && m.x[2,i] >= grid.yc[celly+1] ? 1 : 0
        
        wx::Float64 = (m.x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx]) # mdx/dx
        wy::Float64 = (m.x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
        
        mfield[1,i] = (1.0-wx)*(1.0-wy)*field[celly,cellx] +
            + (wx)*(1.0-wy)*field[celly,cellx+1] +
            + (1.0-wx)*(wy)*field[celly+1,cellx] +
            + (wx)*(wy)*field[celly+1,cellx+1]
    end
end

function cell_center_change_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix{Float64},mfield::String)
    if size(field,1) == grid.nx+1
        cellx_max = grid.nx
    else
        cellx_max = grid.nx-1
    end
    if size(field,2) == grid.ny+1
        celly_max = grid.ny
    else
        celly_max = grid.ny-1
    end
    k = m.scalarFields[mfield]
    Threads.@threads for i in 1:m.nmark
        local cellx::Int64 = m.cell[1,i]
        local celly::Int64 = m.cell[2,i]
        
        cellx += cellx < cellx_max && m.x[1,i] >= grid.xc[cellx+1] ? 1 : 0
         celly = m.cell[2,i]
         celly += celly < celly_max && m.x[2,i] >= grid.yc[celly+1] ? 1 : 0
        
        wx::Float64 = (m.x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx]) # mdx/dx
        wy::Float64 = (m.x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
        
        m.scalars[k,i] += (1.0-wx)*(1.0-wy)*field[celly,cellx] +
            + (wx)*(1.0-wy)*field[celly,cellx+1] +
            + (1.0-wx)*(wy)*field[celly+1,cellx] +
            + (wx)*(wy)*field[celly+1,cellx+1]
    end
end

function basic_node_change_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix{Float64},mfield::String)
    k = m.scalarFields[mfield]
    Threads.@threads for i in 1:m.nmark
        cellx::Int64 = m.cell[1,i]
        celly::Int64 = m.cell[2,i]
        wx::Float64 = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
        wy::Float64 = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
        
        m.scalars[k,i] += (1.0-wx)*(1.0-wy)*field[celly,cellx] +
            + (wx)*(1.0-wy)*field[celly,cellx+1] +
            + (1.0-wx)*(wy)*field[celly+1,cellx] +
            + (wx)*(wy)*field[celly+1,cellx+1]
    end
end

# function basic_node_to_markers!(m::Markers,grid::CartesianGrid,field::Matrix)
#     Threads.@threads for i in 1:m.nmark
#         cellx = m.cell[1,i]
#         celly = m.cell[2,i]
#         wx::Float64 = (m.x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx]) # mdx/dx
#         wy::Float64 = (m.x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
        
#         m.rho[i] = (1.0-wx)*(1.0-wy)*field[celly,cellx] +
#             + (wx)*(1.0-wy)*field[celly,cellx+1] +
#             + (1.0-wx)*(wy)*field[celly+1,cellx] +
#             + (wx)*(wy)*field[celly+1,cellx+1]
#     end
# end

function viscosity_to_cell_centers(grid::CartesianGrid,etas::Matrix{Float64})
    # compute the harmonic average of the viscosities at the nodal points
    etan = zeros(grid.ny,grid.nx)
    for i in 2:grid.ny
        for j in 2:grid.nx
            etan[i,j] = 1/( (1/etas[i-1,j-1] + 1/etas[i-1,j] + 1/etas[i,j-1] + 1/etas[i,j])/4. )
        end
    end
    return etan
end

function velocity_to_centers(grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64})
    # compute vx and vy at cell centers
     vxc = zeros(grid.ny+1,grid.nx+1);
     vyc = zeros(grid.ny+1,grid.nx+1);
     # cell centers are offset in (-) direction from basic nodes.
     #               |
     # (center)     vx[i,j]
     #               |
     # ---vy[i,j]---(i,j)       
     for i in 2:grid.ny        # interior...
        for j in 2:grid.nx
            # left
            vxm = vx[i,j-1] # this will produce vx=0 along the left boundary
            vxp = vx[i,j]
            # top
            vym = vy[i-1,j] # vy=0 along the top boundary
            vyp = vy[i,j]
            vxc[i,j] = 0.5*(vxp+vxm)
            vyc[i,j] = 0.5*(vyp+vym)            
        end
    end
    # vx - top
    vxc[1,2:grid.nx] = vxc[2,2:grid.nx]
    # bottom
    vxc[grid.ny+1,2:grid.nx] = vxc[grid.ny,2:grid.nx]
    # left
    vxc[:,1] = -vxc[:,2]
    # right
    vxc[:,grid.nx+1] = - vxc[:,grid.nx]

    # vy - left
    vyc[2:grid.ny,1] = vyc[2:grid.ny,2]
    # vy - right
    vyc[2:grid.ny,grid.nx+1] = vyc[2:grid.ny,grid.nx]
    # vy - top
    vyc[1,:] = -vyc[2,:]
    # vy - bottom
    vyc[grid.ny+1,:] = -vyc[grid.ny,:]        
    
    return vxc,vyc
end

function velocity_to_basic_nodes(grid::CartesianGrid,vxc::Matrix{Float64},vyc::Matrix{Float64})
    # this gets the velocity in a format suitable for visualization.
    # NOTE - performs a transpose on the grid!!!
    vn = Array{Float64,3}(undef,2,grid.nx,grid.ny)
    for i in 1:grid.ny
        for j in 1:grid.nx
            vn[1,j,i] = 0.25*(vxc[i,j]+vxc[i+1,j]+vxc[i,j+1]+vxc[i+1,j+1])
            vn[2,j,i] = 0.25*(vyc[i,j]+vyc[i+1,j]+vyc[i,j+1]+vyc[i+1,j+1])
        end
    end
    return vn
end

function velocity_to_points(x::Matrix{Float64},cell::Matrix{Int64},grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64}; continuity_weight::Float64=0.0,N::Int64=-1,vxc=nothing,vyc=nothing)
    # compute the velocity at points, using the continuity-based velocity interpolation
    # compute velocity at cell centers
    # compute the velocity at the markers from the velocity nodes:
    mvx,mvy = velocity_nodes_to_points(x,cell,grid,vx,vy)
    if continuity_weight == 0.0
        return mvx,mvy
    end

    # compute velocity at cell centers
    if vxc == nothing || vyc == nothing
        vxc,vyc = velocity_to_centers(grid,vx,vy);
    end
    # compute the velocity at the markers from the cell centers:
    mvxc,mvyc = velocity_center_to_points(x,cell,grid,vxc,vyc)

    mvx = continuity_weight*(mvxc) + (1.0-continuity_weight)*(mvx)
    mvy = continuity_weight*(mvyc) + (1.0-continuity_weight)*(mvy)
    return mvx,mvy
end

function velocity_nodes_to_points(x::Matrix{Float64},cell::Matrix{Int64},grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64};N::Int64=-1)
    # compute velocity at N points given in x (2-by-N
    # cell should contain the cells in which the points are located (2-by-N)
    # this routine assumes that the velocity (vxc and vyc) is defined AT THE VELOCITY NODES
    if N==-1
        N = size(x,2)
    end
    mvx = Array{Float64,1}(undef,N) # x-velocities at specified locations
    Threads.@threads for i in 1:N
        #interpolation of vx. vx cells are staggered in the -y direction
        cellx::Int64 = cell[1,i]
        celly::Int64 = x[2,i] < grid.yc[cell[2,i]+1] ? cell[2,i] : cell[2,i] + 1
        mdx::Float64 = (x[1,i] - grid.x[cellx])/(grid.x[cellx+1]-grid.x[cellx])
        mdy::Float64 = (x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
        mvx[i] = (1-mdx)*(1-mdy)*vx[celly,cellx] +
            + (mdx)*(1-mdy)*vx[celly,cellx+1] +
            + (1-mdx)*(mdy)*vx[celly+1,cellx] +
            + (mdx)*(mdy)*vx[celly+1,cellx+1]

    end    
    mvy = Array{Float64,1}(undef,N) # y-velocities at specified locations
    Threads.@threads for i in 1:N
    # interpolation of vy. vy cells are staggered in the -x direction
        cellx::Int64 = x[1,i] < grid.xc[cell[1,i]+1] ? cell[1,i] : cell[1,i] + 1
        celly::Int64 = cell[2,i]
        mdx::Float64 = (x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx])
        mdy::Float64 = (x[2,i] - grid.y[celly])/(grid.y[celly+1]-grid.y[celly])
        mvy[i] = (1-mdx)*(1-mdy)*vy[celly,cellx] +
            + (mdx)*(1-mdy)*vy[celly,cellx+1] +
            + (1-mdx)*(mdy)*vy[celly+1,cellx] +
            + (mdx)*(mdy)*vy[celly+1,cellx+1]
    end
    return mvx,mvy
end

function velocity_center_to_points(x::Matrix{Float64},cell::Matrix{Int64},grid::CartesianGrid,vxc::Matrix{Float64},vyc::Matrix{Float64};N=-1)
    # compute velocity at N points given in x (2-by-N)
    # cell should contain the cells in which the points are located (2-by-N)
    # this routine assumes that the velocity (vxc and vyc) is defined at the cell centers
    if N==-1
        N = size(x,2)
    end
    mvx = Array{Float64,1}(undef,N) # velocities at specified locations
    mvy = Array{Float64,1}(undef,N) 
    Threads.@threads for i in 1:N
        local cellx::Int64 = x[1,i] < grid.xc[cell[1,i]+1] ? cell[1,i] : cell[1,i] + 1
        local celly::Int64 = x[2,i] < grid.yc[cell[2,i]+1] ? cell[2,i] : cell[2,i] + 1
        local mdx::Float64 = (x[1,i] - grid.xc[cellx])/(grid.xc[cellx+1]-grid.xc[cellx])
        local mdy::Float64 = (x[2,i] - grid.yc[celly])/(grid.yc[celly+1]-grid.yc[celly])
        mvx[i] = (1-mdx)*(1-mdy)*vxc[celly,cellx] +
            + (mdx)*(1-mdy)*vxc[celly,cellx+1] +
            + (1-mdx)*(mdy)*vxc[celly+1,cellx] +
            + (mdx)*(mdy)*vxc[celly+1,cellx+1]
        mvy[i] = (1-mdx)*(1-mdy)*vyc[celly,cellx] +
            + (mdx)*(1-mdy)*vyc[celly,cellx+1] +
            + (1-mdx)*(mdy)*vyc[celly+1,cellx] +
            + (mdx)*(mdy)*vyc[celly+1,cellx+1]
    end    
    return mvx,mvy
end

function velocity_to_markers(m::Markers,grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64};vxc=nothing,vyc=nothing,continuity_weight::Float64=0.0)
    # This function expects the velocities to be defined at the cell centers. vxc and vyc should each have
    # an 'extra' column and row corresponding to the ghost degrees of freedom that are needed to interpolate
    # velocities along the bottom and left of the domain.
    mvx,mvy = velocity_to_points(m.x,m.cell,grid,vx,vy;continuity_weight=continuity_weight,N=m.nmark)
    return mvx,mvy
end

function move_markers!(markers::Markers,grid::CartesianGrid,vxc::Matrix{Float64},vyc::Matrix{Float64},dt::Float64)
    # move the markers using the 1st-order algorithm (forward Euler)
    mvx,mvy = velocity_to_markers(markers,grid,vxc,vyc)
    # determine the maximal timestep
    vxmax = maximum(abs.(mvx))
    vymax = maximum(abs.(mvy))
    Threads.@threads for i in 1:markers.nmark
        markers.x[1,i] += dt*mvx[i]
        markers.x[2,i] += dt*mvy[i]
    end    
    find_cells!(markers,grid)
    return dt
end

function move_markers_rk2!(markers::Markers,grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64},dt::Float64;continuity_weight::Float64=1.0/3.0)
    # move the markers using the 2nd-order Runge-Kutta algorithm.
    # compute velocities for each marker at current position
    mvx::Vector{Float64}, mvy::Vector{Float64} = velocity_to_markers(markers,grid,vx,vy,continuity_weight=continuity_weight)
    # compute marker location at xA, xB
    xB = Array{Float64,2}(undef,2,markers.nmark)
    for i in 1:markers.nmark
        xB[1,i] = markers.x[1,i] + dt/2*mvx[i]
        xB[2,i] = markers.x[2,i] + dt/2*mvy[i]
    end
    # re-locate markers, which may now be in a different cell.
    cell::Matrix{Int64} = copy(markers.cell)
    Threads.@threads for i in 1:markers.nmark
        cell[1,i] = find_cell(xB[1,i], grid.x, grid.nx, guess=cell[1,i])
        cell[2,i] = find_cell(xB[2,i], grid.y, grid.ny, guess=cell[2,i])
    end
    # compute velocity at xB
    mvx, mvy = velocity_to_points(xB,cell,grid,vxc,vyc,continuity_weight=continuity_weight)
    # Move the markers using the velocity at xB.
     for i in 1:markers.nmark
         markers.x[1,i] += dt*mvx[i]
         markers.x[2,i] += dt*mvy[i]
     end    
    # re-locate markers in their new cells.
    find_cells!(markers,grid)
end

function move_markers_rk4!(markers::Markers,grid::CartesianGrid,vx::Matrix{Float64},vy::Matrix{Float64},dt::Float64; continuity_weight::Float64=1.0/3.0)
    # This function implements the 4th-order Runge-Kutta scheme for advection of markers. It expects
    # vxc and vyc are the velocities at the velocity nodes
    # dt is the timestep
    if continuity_weight != 0.0
        vxc,vyc = velocity_to_centers(grid,vx,vy)
    else
        vxc=nothing
        vyc=nothing
    end
    # 1. compute velocity at point A
    vxA::Vector{Float64}, vyA::Vector{Float64} = velocity_to_markers(markers,grid,vx,vy,continuity_weight=continuity_weight,vxc=vxc,vyc=vyc)
    # 2. compute xB=xA + vA*dt/2
    xB = Array{Float64,2}(undef,2,markers.nmark)
    for i in 1:markers.nmark
        xB[1,i] = markers.x[1,i] + dt/2*vxA[i]
        xB[2,i] = markers.x[2,i] + dt/2*vyA[i]
    end
    # 3. locate xB and compute vxB
    cell::Matrix{Int64} = copy(markers.cell)
    Threads.@threads for i in 1:markers.nmark
        cell[1,i] = find_cell(xB[1,i], grid.x, grid.nx, guess=cell[1,i])
        cell[2,i] = find_cell(xB[2,i], grid.y, grid.ny, guess=cell[2,i])
    end
    vxB, vyB = velocity_to_points(xB,cell,grid,vx,vy,continuity_weight=continuity_weight,vxc=vxc,vyc=vyc)
    # 4. compute xC = xA+vB*dt/2
    xC = Array{Float64,2}(undef,2,markers.nmark)
    for i in 1:markers.nmark
        xC[1,i] = markers.x[1,i] + dt/2*vxB[i]
        xC[2,i] = markers.x[2,i] + dt/2*vyB[i]
    end
    # 5. locate cells for xC and compute vC
    Threads.@threads for i in 1:markers.nmark
        cell[1,i] = find_cell(xC[1,i], grid.x, grid.nx, guess=cell[1,i])
        cell[2,i] = find_cell(xC[2,i], grid.y, grid.ny, guess=cell[2,i])
    end
    vxC, vyC = velocity_to_points(xC,cell,grid,vx,vy,continuity_weight=continuity_weight,vxc=vxc,vyc=vyc)
    # 6. compute xD = xA + vC*dt
    xD = Array{Float64,2}(undef,2,markers.nmark)
    for i in 1:markers.nmark
        xD[1,i] = markers.x[1,i] + dt*vxC[i]
        xD[2,i] = markers.x[2,i] + dt*vyC[i]
    end
    # 7. locate cells for xD and compute vD
    Threads.@threads for i in 1:markers.nmark
        cell[1,i] = find_cell(xD[1,i], grid.x, grid.nx, guess=cell[1,i])
        cell[2,i] = find_cell(xD[2,i], grid.y, grid.ny, guess=cell[2,i])
    end
    vxD, vyD = velocity_to_points(xD,cell,grid,vx,vy,continuity_weight=continuity_weight,vxc=vxc,vyc=vyc)
    # 8. Compute v_eff = 1/6*(vA+2*vB+2*vC+vD) and move markers by v_eff*dt
    Threads.@threads for i in 1:markers.nmark
        markers.x[1,i] += dt/6.0*(vxA[i] + 2*vxB[i] + 2*vxC[i] + vxD[i]) 
        markers.x[2,i] += dt/6.0*(vyA[i] + 2*vyB[i] + 2*vyC[i] + vyD[i])
    end
    # 9. relocate markers in their cells.
    find_cells!(markers,grid)
end


