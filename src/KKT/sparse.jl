
"""
    SparseKKTSystem{T, VT, MT, QN} <: AbstractReducedKKTSystem{T, VT, MT, QN}

Implement the [`AbstractReducedKKTSystem`](@ref) in sparse COO format.

"""
struct SparseKKTSystem{T, VT, MT, QN} <: AbstractReducedKKTSystem{T, VT, MT, QN}
    hess::VT
    jac_callback::VT
    jac::VT
    quasi_newton::QN
    pr_diag::VT
    du_diag::VT
    # Augmented system
    aug_raw::SparseMatrixCOO{T,Int32,VT}
    aug_com::MT
    aug_csc_map::Union{Nothing, Vector{Int}}
    # Jacobian
    jac_raw::SparseMatrixCOO{T,Int32,VT}
    jac_com::MT
    jac_csc_map::Union{Nothing, Vector{Int}}
    # Info
    ind_ineq::Vector{Int}
    ind_fixed::Vector{Int}
    ind_aug_fixed::Vector{Int}
    jacobian_scaling::VT
end

"""
    SparseUnreducedKKTSystem{T, VT, MT, QN} <: AbstractUnreducedKKTSystem{T, VT, MT, QN}

Implement the [`AbstractUnreducedKKTSystem`](@ref) in sparse COO format.

"""
struct SparseUnreducedKKTSystem{T, VT, MT, QN} <: AbstractUnreducedKKTSystem{T, VT, MT, QN}
    hess::VT
    jac_callback::VT
    jac::VT
    quasi_newton::QN
    pr_diag::VT
    du_diag::VT

    l_diag::VT
    u_diag::VT
    l_lower::VT
    u_lower::VT
    aug_raw::SparseMatrixCOO{T,Int32,VT}
    aug_com::MT
    aug_csc_map::Union{Nothing, Vector{Int}}

    jac_raw::SparseMatrixCOO{T,Int32,VT}
    jac_com::MT
    jac_csc_map::Union{Nothing, Vector{Int}}
    ind_ineq::Vector{Int}
    ind_fixed::Vector{Int}
    ind_aug_fixed::Vector{Int}
    jacobian_scaling::VT
end

# Template to dispatch on sparse representation
const AbstractSparseKKTSystem{T, VT, MT, QN} = Union{
    SparseKKTSystem{T, VT, MT, QN},
    SparseUnreducedKKTSystem{T, VT, MT, QN},
}

#=
    Generic sparse methods
=#
function build_hessian_structure(nlp::AbstractNLPModel, ::Type{<:ExactHessian})
    hess_I = Vector{Int32}(undef, get_nnzh(nlp.meta))
    hess_J = Vector{Int32}(undef, get_nnzh(nlp.meta))
    hess_structure!(nlp,hess_I,hess_J)
    return hess_I, hess_J
end
# NB. Quasi-Newton methods require only the sparsity pattern
#     of the diagonal term to store the term ξ I.
function build_hessian_structure(nlp::AbstractNLPModel, ::Type{<:AbstractQuasiNewton})
    hess_I = collect(Int32, 1:get_nvar(nlp))
    hess_J = collect(Int32, 1:get_nvar(nlp))
    return hess_I, hess_J
end

function mul!(y::AbstractVector, kkt::AbstractSparseKKTSystem, x::AbstractVector)
    mul!(y, Symmetric(kkt.aug_com, :L), x)
end
function mul!(y::AbstractKKTVector, kkt::AbstractSparseKKTSystem, x::AbstractKKTVector)
    mul!(full(y), Symmetric(kkt.aug_com, :L), full(x))
end

function jtprod!(y::AbstractVector, kkt::AbstractSparseKKTSystem, x::AbstractVector)
    mul!(y, kkt.jac_com', x)
end

get_jacobian(kkt::AbstractSparseKKTSystem) = kkt.jac_callback

nnz_jacobian(kkt::AbstractSparseKKTSystem) = nnz(kkt.jac_raw)

function compress_jacobian!(kkt::AbstractSparseKKTSystem{T, VT, MT}) where {T, VT, MT<:SparseMatrixCSC{T, Int32}}
    ns = length(kkt.ind_ineq)
    kkt.jac[end-ns+1:end] .= -1.0
    kkt.jac .*= kkt.jacobian_scaling # scaling
    transfer!(kkt.jac_com, kkt.jac_raw, kkt.jac_csc_map)
end

function compress_jacobian!(kkt::AbstractSparseKKTSystem{T, VT, MT}) where {T, VT, MT<:Matrix{T}}
    ns = length(kkt.ind_ineq)
    kkt.jac[end-ns+1:end] .= -1.0
    kkt.jac .*= kkt.jacobian_scaling # scaling
    copyto!(kkt.jac_com, kkt.jac_raw)
end

function set_jacobian_scaling!(kkt::AbstractSparseKKTSystem{T, VT, MT}, constraint_scaling::AbstractVector) where {T, VT, MT}
    nnzJ = length(kkt.jac)::Int
    @inbounds for i in 1:nnzJ
        index = kkt.jac_raw.I[i]
        kkt.jacobian_scaling[i] = constraint_scaling[index]
    end
end


#=
    SparseKKTSystem
=#

function SparseKKTSystem{T, VT, MT, QN}(
    n::Int, m::Int, ind_ineq::Vector{Int}, ind_fixed::Vector{Int},
    hess_sparsity_I, hess_sparsity_J,
    jac_sparsity_I, jac_sparsity_J,
) where {T, VT, MT, QN}
    n_slack = length(ind_ineq)
    n_jac = length(jac_sparsity_I)
    n_hess = length(hess_sparsity_I)
    n_tot = n + n_slack

    aug_vec_length = n_tot+m
    aug_mat_length = n_tot+m+n_hess+n_jac+n_slack

    I = Vector{Int32}(undef, aug_mat_length)
    J = Vector{Int32}(undef, aug_mat_length)
    V = VT(undef, aug_mat_length)
    fill!(V, 0.0)  # Need to initiate V to avoid NaN

    offset = n_tot+n_jac+n_slack+n_hess+m

    I[1:n_tot] .= 1:n_tot
    I[n_tot+1:n_tot+n_hess] = hess_sparsity_I
    I[n_tot+n_hess+1:n_tot+n_hess+n_jac] .= (jac_sparsity_I.+n_tot)
    I[n_tot+n_hess+n_jac+1:n_tot+n_hess+n_jac+n_slack] .= ind_ineq .+ n_tot
    I[n_tot+n_hess+n_jac+n_slack+1:offset] .= (n_tot+1:n_tot+m)

    J[1:n_tot] .= 1:n_tot
    J[n_tot+1:n_tot+n_hess] = hess_sparsity_J
    J[n_tot+n_hess+1:n_tot+n_hess+n_jac] .= jac_sparsity_J
    J[n_tot+n_hess+n_jac+1:n_tot+n_hess+n_jac+n_slack] .= (n+1:n+n_slack)
    J[n_tot+n_hess+n_jac+n_slack+1:offset] .= (n_tot+1:n_tot+m)

    pr_diag = _madnlp_unsafe_wrap(V, n_tot)
    du_diag = _madnlp_unsafe_wrap(V, m, n_jac+n_slack+n_hess+n_tot+1)

    hess = _madnlp_unsafe_wrap(V, n_hess, n_tot+1)
    jac = _madnlp_unsafe_wrap(V, n_jac+n_slack, n_hess+n_tot+1)
    jac_callback = _madnlp_unsafe_wrap(V, n_jac, n_hess+n_tot+1)

    aug_raw = SparseMatrixCOO(aug_vec_length,aug_vec_length,I,J,V)
    jac_raw = SparseMatrixCOO(
        m, n_tot,
        Int32[jac_sparsity_I; ind_ineq],
        Int32[jac_sparsity_J; n+1:n+n_slack],
        jac,
    )

    aug_com = MT(aug_raw)
    jac_com = MT(jac_raw)

    aug_csc_map = get_mapping(aug_com, aug_raw)
    jac_csc_map = get_mapping(jac_com, jac_raw)

    ind_aug_fixed = if isa(aug_com, SparseMatrixCSC)
        _get_fixed_variable_index(aug_com, ind_fixed)
    else
        zeros(Int, 0)
    end
    jac_scaling = ones(T, n_jac+n_slack)

    quasi_newton = QN(n)

    return SparseKKTSystem{T, VT, MT, QN}(
        hess, jac_callback, jac, quasi_newton, pr_diag, du_diag,
        aug_raw, aug_com, aug_csc_map,
        jac_raw, jac_com, jac_csc_map,
        ind_ineq, ind_fixed, ind_aug_fixed, jac_scaling,
    )
end

# Build KKT system directly from AbstractNLPModel
function SparseKKTSystem{T, VT, MT, QN}(nlp::AbstractNLPModel, ind_cons=get_index_constraints(nlp)) where {T, VT, MT, QN}
    n_slack = length(ind_cons.ind_ineq)
    # Deduce KKT size.
    n = get_nvar(nlp)
    m = get_ncon(nlp)
    # Evaluate sparsity pattern
    jac_I = Vector{Int32}(undef, get_nnzj(nlp.meta))
    jac_J = Vector{Int32}(undef, get_nnzj(nlp.meta))
    jac_structure!(nlp,jac_I, jac_J)

    hess_I, hess_J = build_hessian_structure(nlp, QN)

    force_lower_triangular!(hess_I,hess_J)

    return SparseKKTSystem{T, VT, MT, QN}(
        n, m, ind_cons.ind_ineq, ind_cons.ind_fixed,
        hess_I, hess_J, jac_I, jac_J,
    )
end

is_reduced(::SparseKKTSystem) = true
num_variables(kkt::SparseKKTSystem) = length(kkt.pr_diag)


#=
    SparseUnreducedKKTSystem
=#

function SparseUnreducedKKTSystem{T, VT, MT, QN}(
    n::Int, m::Int, nlb::Int, nub::Int, ind_ineq, ind_fixed,
    hess_sparsity_I, hess_sparsity_J,
    jac_sparsity_I, jac_sparsity_J,
    ind_lb, ind_ub,
) where {T, VT, MT, QN}
    n_slack = length(ind_ineq)
    n_jac = length(jac_sparsity_I)
    n_hess = length(hess_sparsity_I)
    n_tot = n + n_slack

    aug_mat_length = n_tot + m + n_hess + n_jac + n_slack + 2*nlb + 2*nub
    aug_vec_length = n_tot + m + nlb + nub

    I = Vector{Int32}(undef, aug_mat_length)
    J = Vector{Int32}(undef, aug_mat_length)
    V = zeros(aug_mat_length)

    offset = n_tot + n_jac + n_slack + n_hess + m

    I[1:n_tot] .= 1:n_tot
    I[n_tot+1:n_tot+n_hess] = hess_sparsity_I
    I[n_tot+n_hess+1:n_tot+n_hess+n_jac].=(jac_sparsity_I.+n_tot)
    I[n_tot+n_hess+n_jac+1:n_tot+n_hess+n_jac+n_slack].=(ind_ineq.+n_tot)
    I[n_tot+n_hess+n_jac+n_slack+1:offset].=(n_tot+1:n_tot+m)

    J[1:n_tot] .= 1:n_tot
    J[n_tot+1:n_tot+n_hess] = hess_sparsity_J
    J[n_tot+n_hess+1:n_tot+n_hess+n_jac] .= jac_sparsity_J
    J[n_tot+n_hess+n_jac+1:n_tot+n_hess+n_jac+n_slack] .= (n+1:n+n_slack)
    J[n_tot+n_hess+n_jac+n_slack+1:offset].=(n_tot+1:n_tot+m)

    I[offset+1:offset+nlb] .= (1:nlb).+(n_tot+m)
    I[offset+nlb+1:offset+2nlb] .= (1:nlb).+(n_tot+m)
    I[offset+2nlb+1:offset+2nlb+nub] .= (1:nub).+(n_tot+m+nlb)
    I[offset+2nlb+nub+1:offset+2nlb+2nub] .= (1:nub).+(n_tot+m+nlb)
    J[offset+1:offset+nlb] .= (1:nlb).+(n_tot+m)
    J[offset+nlb+1:offset+2nlb] .= ind_lb
    J[offset+2nlb+1:offset+2nlb+nub] .= (1:nub).+(n_tot+m+nlb)
    J[offset+2nlb+nub+1:offset+2nlb+2nub] .= ind_ub

    pr_diag = _madnlp_unsafe_wrap(V,n_tot)
    du_diag = _madnlp_unsafe_wrap(V,m, n_jac + n_slack+n_hess+n_tot+1)

    l_diag = _madnlp_unsafe_wrap(V, nlb, offset+1)
    l_lower= _madnlp_unsafe_wrap(V, nlb, offset+nlb+1)
    u_diag = _madnlp_unsafe_wrap(V, nub, offset+2nlb+1)
    u_lower= _madnlp_unsafe_wrap(V, nub, offset+2nlb+nub+1)

    hess = _madnlp_unsafe_wrap(V, n_hess, n_tot+1)
    jac = _madnlp_unsafe_wrap(V, n_jac + n_slack, n_hess+n_tot+1)
    jac_callback = _madnlp_unsafe_wrap(V, n_jac, n_hess+n_tot+1)

    aug_raw = SparseMatrixCOO(aug_vec_length,aug_vec_length,I,J,V)
    jac_raw = SparseMatrixCOO(
        m, n_tot,
        Int32[jac_sparsity_I; ind_ineq],
        Int32[jac_sparsity_J; n+1:n+n_slack],
        jac,
    )

    aug_com = MT(aug_raw)
    jac_com = MT(jac_raw)

    aug_csc_map = get_mapping(aug_com, aug_raw)
    jac_csc_map = get_mapping(jac_com, jac_raw)

    jac_scaling = ones(T, n_jac+n_slack)

    ind_aug_fixed = if isa(aug_com, SparseMatrixCSC)
        _get_fixed_variable_index(aug_com, ind_fixed)
    else
        zeros(Int, 0)
    end

    quasi_newton = QN(n)

    return SparseUnreducedKKTSystem{T, VT, MT, QN}(
        hess, jac_callback, jac, quasi_newton, pr_diag, du_diag,
        l_diag, u_diag, l_lower, u_lower,
        aug_raw, aug_com, aug_csc_map,
        jac_raw, jac_com, jac_csc_map,
        ind_ineq, ind_fixed, ind_aug_fixed, jac_scaling,
    )
end

function SparseUnreducedKKTSystem{T, VT, MT, QN}(nlp::AbstractNLPModel, ind_cons=get_index_constraints(nlp)) where {T, VT, MT, QN}
    n_slack = length(ind_cons.ind_ineq)
    nlb = length(ind_cons.ind_lb)
    nub = length(ind_cons.ind_ub)
    # Deduce KKT size.
    n = get_nvar(nlp)
    m = get_ncon(nlp)
    # Evaluate sparsity pattern
    jac_I = Vector{Int32}(undef, get_nnzj(nlp.meta))
    jac_J = Vector{Int32}(undef, get_nnzj(nlp.meta))
    jac_structure!(nlp,jac_I, jac_J)

    hess_I = Vector{Int32}(undef, get_nnzh(nlp.meta))
    hess_J = Vector{Int32}(undef, get_nnzh(nlp.meta))
    hess_structure!(nlp,hess_I,hess_J)

    force_lower_triangular!(hess_I,hess_J)

    return SparseUnreducedKKTSystem{T, VT, MT, QN}(
        n, m, nlb, nub, ind_cons.ind_ineq, ind_cons.ind_fixed,
        hess_I, hess_J, jac_I, jac_J, ind_cons.ind_lb, ind_cons.ind_ub,
    )
end

function initialize!(kkt::SparseUnreducedKKTSystem)
    kkt.pr_diag.=1
    kkt.du_diag.=0
    kkt.hess.=0
    kkt.l_lower.=0
    kkt.u_lower.=0
    kkt.l_diag.=1
    kkt.u_diag.=1
end

is_reduced(::SparseUnreducedKKTSystem) = false
num_variables(kkt::SparseUnreducedKKTSystem) = length(kkt.pr_diag)

