
"""
    AbstractKKTVector{T, VT}

Supertype for KKT's right-hand-side vectors ``(x, s, y, z, ν, w)``.
"""
abstract type AbstractKKTVector{T, VT} end

"""
    full(X::AbstractKKTVector)

Return the all the values stored inside the KKT vector `X`.
"""
function full end

Base.length(rhs::AbstractKKTVector) = length(full(rhs))

"""
    number_primal(X::AbstractKKTVector)

Get total number of primal values ``(x, s)`` in KKT vector `X`.
"""
number_primal(rhs::AbstractKKTVector) = length(primal(rhs))

"""
    number_dual(X::AbstractKKTVector)

Get total number of dual values ``(y, z)`` in KKT vector `X`.
"""
number_dual(rhs::AbstractKKTVector) = length(dual(rhs))

"""
    primal(X::AbstractKKTVector)

Return the primal values ``(x, s)`` stored in the KKT vector `X`.
"""
function primal end

"""
    dual(X::AbstractKKTVector)

Return the dual values ``(y, z)`` stored in the KKT vector `X`.
"""
function dual end

"""
    primal_dual(X::AbstractKKTVector)

Return both the primal and the dual values ``(x, s, y, z)`` stored in the KKT vector `X`.
"""
function primal_dual end

"""
    dual_lb(X::AbstractKKTVector)

Return the dual values ``ν`` associated to the lower-bound
stored in the KKT vector `X`.
"""
function dual_lb end

"""
    dual_ub(X::AbstractKKTVector)

Return the dual values ``w`` associated to the upper-bound
stored in the KKT vector `X`.
"""
function dual_ub end

function Base.fill!(rhs::AbstractKKTVector{T}, val::T) where T
    fill!(full(rhs), val)
end

# Overload basic BLAS operations.
norm(X::AbstractKKTVector, p::Real) = norm(full(X), p)
dot(X::AbstractKKTVector, Y::AbstractKKTVector) = dot(full(X), full(Y))
function axpy!(a::Number, X::AbstractKKTVector, Y::AbstractKKTVector)
    axpy!(a, full(X), full(Y))
end

#=
    ReducedKKTVector
=#

"""
    ReducedKKTVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}

KKT vector ``(x, s, y, z)``, associated to a [`AbstractReducedKKTSystem`](@ref).

Compared to [`UnreducedKKTVector`](@ref), it does not store
the dual values associated to the primal's lower and upper bounds.
"""
struct ReducedKKTVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}
    values::VT
    xp::VT # unsafe view
    xl::VT # unsafe view
end

ReducedKKTVector{T,VT}(n::Int, m::Int, nlb::Int, nub::Int) where {T, VT <: AbstractVector{T}} = ReducedKKTVector{T,VT}(n, m)
function ReducedKKTVector{T,VT}(n::Int, m::Int) where {T, VT <: AbstractVector{T}}
    x = VT(undef, n + m)
    fill!(x, 0.0)
    # Wrap directly array x to avoid dealing with views
    xp = _madnlp_unsafe_wrap(x, n)
    xl = _madnlp_unsafe_wrap(x, m, n+1)
    return ReducedKKTVector{T, VT}(x, xp, xl)
end
function ReducedKKTVector(rhs::AbstractKKTVector)
    return ReducedKKTVector(number_primal(rhs), number_dual(rhs))
end

full(rhs::ReducedKKTVector) = rhs.values
primal(rhs::ReducedKKTVector) = rhs.xp
dual(rhs::ReducedKKTVector) = rhs.xl
primal_dual(rhs::ReducedKKTVector) = rhs.values


#=
    UnreducedKKTVector
=#

"""
    UnreducedKKTVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}

Full KKT vector ``(x, s, y, z, ν, w)``, associated to a [`AbstractUnreducedKKTSystem`](@ref).

"""
struct UnreducedKKTVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}
    values::VT
    x::VT  # unsafe view
    xp::VT # unsafe view
    xl::VT # unsafe view
    xzl::VT # unsafe view
    xzu::VT # unsafe view
end

function UnreducedKKTVector{T, VT}(n::Int, m::Int, nlb::Int, nub::Int) where {T, VT <: AbstractVector{T}}
    values = VT(undef,n+m+nlb+nub)
    fill!(values, 0.0)
    # Wrap directly array x to avoid dealing with views
    x = _madnlp_unsafe_wrap(values, n + m) # Primal-Dual
    xp = _madnlp_unsafe_wrap(values, n) # Primal
    xl = _madnlp_unsafe_wrap(values, m, n+1) # Dual
    xzl = _madnlp_unsafe_wrap(values, nlb, n + m + 1) # Lower bound
    xzu = _madnlp_unsafe_wrap(values, nub, n + m + nlb + 1) # Upper bound
    return UnreducedKKTVector{T, VT}(values, x, xp, xl, xzl, xzu)
end

full(rhs::UnreducedKKTVector) = rhs.values
primal(rhs::UnreducedKKTVector) = rhs.xp
dual(rhs::UnreducedKKTVector) = rhs.xl
primal_dual(rhs::UnreducedKKTVector) = rhs.x
dual_lb(rhs::UnreducedKKTVector) = rhs.xzl
dual_ub(rhs::UnreducedKKTVector) = rhs.xzu


"""
    PrimalVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}

Primal vector ``(x, s)``.

"""
struct PrimalVector{T, VT<:AbstractVector{T}} <: AbstractKKTVector{T, VT}
    values::VT
    x::VT  # unsafe view
    s::VT # unsafe view
end

function PrimalVector{T, VT}(nx::Int, ns::Int) where {T, VT <: AbstractVector{T}}
    values = VT(undef, nx+ns) ; fill!(values, zero(T))
    return PrimalVector{T, VT}(
        values,
        _madnlp_unsafe_wrap(values, nx),
        _madnlp_unsafe_wrap(values, ns, nx+1),
    )
end

full(rhs::PrimalVector) = rhs.values
primal(rhs::PrimalVector) = rhs.values
variable(rhs::PrimalVector) = rhs.x
slack(rhs::PrimalVector) = rhs.s

