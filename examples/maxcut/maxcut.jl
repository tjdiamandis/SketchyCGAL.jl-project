include("utils.jl")
using JuMP, MosekTools

G = graph_from_file(joinpath(@__DIR__, "data/G1"))
n = size(G, 1)

function solve_with_jump(C)
    sdp = Model(Mosek.Optimizer)
    @variable(sdp, X[1:n, 1:n] in PSDCone())
    @constraint(sdp, diag(X) .== 1)
    @objective(sdp, Min, sum(C.*X))
    optimize!(sdp)
    Xopt = value.(X)
    # Xopt[diagind(X)] .= ones(n)
    return Xopt
end



## ---------- Problem setup ----------
# Parameters
n = size(G, 1)
d = n

# Data
C = -0.25*(Diagonal(G*ones(n)) - G)
b = ones(n)

# Scaling variables -- so trace is bounded by 1
scale_C = 1 / norm(C)
scale_X = 1 / n
# b .= b .* scale_X


# Linear map
# AX = diag(X)
function A!(y, X)
    n = size(X, 1)
    for i in 1:n
        y[i] = X[i,i]
    end
    return nothing
end

# Adjoint
# A*z = Diagonal(z)
function A_adj!(S::SparseMatrixCSC, z)
    for (i, j, v) ∈ zip(findnz(S)...)
        S[i,j] = 0.0
    end
    S[diagind(S)] .= z
    return nothing
 end

# primative 1: u -> C*u
function p1!(v, C, u)
    mul!(v, C, u)
end

#primative 2: (u, z) -> (A*z)u
function p2!(v, u, z)
    v .= u .* z
end

#primative 3: u -> A(uu^T)
function p3!(z, u)
    z .= u.*u
end


## Solve JuMP
Xopt = solve_with_jump(C)
sum(C .* Xopt)

## Solve CGAL
@time XT, yT = cgal_dense(
    Matrix(C), b, A!, A_adj!; n=n, d=d, scale_X=scale_X, scale_C=scale_C,
    max_iters=1_000,
    print_iter=25
)

sum(C .* XT * 1/scale_X)
##
cgal_dense(
    Matrix(C), b, A!, A_adj!; n=n, d=d, scale_X=scale_X, scale_C=scale_C,
    max_iters=400,
    print_iter=25
)

@time BLAS.ger!(η, v, v, Xt)

@btime begin
    Xt .-= η.*Xt
end
@time (@. Xt - η*Xt)
