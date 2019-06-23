module Petri
using ModelingToolkit
import ModelingToolkit: Constant, Variable

struct Model{G,D,L,P}
    g::G
    Δ::D
    Λ::L
    Φ::P
end

Model(δ::D, λ::L, ϕ::P) where {D,L,P} = Model{Any,D,L,P}(missing, δ, λ, ϕ)

struct Problem{M<:Model, S}
    m::M
    initial::S
end

sample(rates) = begin
    s = cumsum(rates)
    r = rand()*s[end]
    nexti = findfirst(s) do x
        x >= r
    end
    return nexti
end

function solve(p::Problem)
    state = p.initial
    for i in 1:10
        state = step(p, state)
    end
    state
end

function step(p::Problem, state)
    @show state
    n = length(p.m.Δ)
    rates = map(p.m.Λ) do λ
        apply(λ, state)
    end
    @show rates
    nexti = sample(rates)
    @show nexti
    if apply(p.m.Φ[nexti], state)
        newval = apply(p.m.Δ[nexti], state)
        eqns = p.m.Δ[nexti]
        for i in 1:length(eqns)
            lhs = eqns[i].lhs
            # rhs = eqns[i].rhs
            setproperty!(state, lhs.op.name, newval[i])
        end
    end
    state
end

function apply(expr::Equation, data)
    rhs = expr.rhs
    apply(rhs, data)
end

function apply(expr::Constant, data)
    # constants don't have an op field they are just a value.
    return expr.value
end

function apply(expr::Tuple, data)
    # this method only exists to harmonize the API for Equation, Constant, and Operation
    # all the real work is happening in the three argument version below.
    vals = map(expr) do ex
        apply(ex, data)
    end
    return tuple(vals...)
end
function apply(expr::Operation, data)
    # this method only exists to harmonize the API for Equation, Constant, and Operation
    # all the real work is happening in the three argument version below.
    apply(expr.op, expr, data)
end

# this uses the operation function as a trait, so that we can dispatch on it;
# allowing client code to extend the language using Multiple Dispatch.
function apply(op::Function, expr::Operation, data)
    # handles the case where there are no more arguments to find.
    # we assume this is a leaf node in the expression, which refers to a field in the data
    if length(expr.args) == 0
        return getproperty(data, expr.op.name)
    end
    anses = map(expr.args) do a
        apply(a, data)
    end
    return op(anses...)
end

end

# using Petri
import Base.show
using DiffEqBase
using ModelingToolkit
# using DiffEqBiological

macro grounding(ex)
    return ()
end

macro reaction(ex)
    :( tuple($ex) )
end


function main(β, γ, μ)
    @grounding begin
        S => Noun(Susceptible, ontology=Snowmed)
        I => Noun(Infectious, ontology=ICD9)
        R => Noun(Recovered, ontology=ICD9)
        λ₁ => Verb(infection)
        λ₂ => Verb(recovery)
        λ₃ => Verb(loss_of_immunity)
    end

    g = @reaction begin
        ( S , I ) -> 2I,
        I -> R,
        R -> S
    end

    # β, 1S + 1I -> 0S + 2I
    # γ, 0R + 1I -> 0I + 1R
    # μ, 1R + 0S -> 1S + 0R

    Δ = [
        (S,I) -> (S-1, I+1),
        (I,R) -> (I-1, R+1),
        (R,S) -> (R-1, S+1),
    ]

    ϕ = [
        (S, I) -> x > 0 && I > 0,
        (I) -> x > 0,
        (R) -> x > 0,
    ]

    Λ = [
        (S,I) -> begin n = +(S,I,R); β*S*I/n end,
        (I) -> begin γ*I end,
        (R) -> begin μ*R end
    ]
    m = Petri.Model(g, Δ, ϕ, Λ)
    @show m
    # d = convert(ODEProblem, m)
    # soln = solve(m) #discrete
    # soln = solve(d) #continuos
end

mutable struct SIRState{T,F}
    S::T
    I::T
    R::T
    β::F
    γ::F
    μ::F
end

function show(io::IO, s::SIRState)
    t = (S=s.S, I=s.I, R=s.R, β=s.β, γ=s.γ, μ=s.μ)
    print(io, "$t")
end


function main′()
    @variables S, I, R, β, γ, μ
    N = +(S,I,R)
    ϕ = [(S > 0) * (I > 0),
         I > 0,
         R > 0]

    Δ = [(S~S-1, I~I+1),
        (I~I-1, R~R+1),
        (R~R-1, S~S+1)]

    Λ = [β*S*I/N,
        γ*I,
        μ*R]

    m = Petri.Model(Δ, Λ, ϕ)
    p = Petri.Problem(m, SIRState(10, 1, 0, 0.5, 0.25, 0.05))
    soln = Petri.solve(p)
end
main′()
