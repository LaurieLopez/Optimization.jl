module OptimizationEvolutionary

using Reexport
@reexport using Evolutionary, Optimization
using Optimization.SciMLBase

SciMLBase.allowsbounds(opt::Evolutionary.AbstractOptimizer) = true
SciMLBase.allowsconstraints(opt::Evolutionary.AbstractOptimizer) = true

decompose_trace(trace::Evolutionary.OptimizationTrace) = last(trace)
decompose_trace(trace::Evolutionary.OptimizationTraceRecord) = trace

function Evolutionary.trace!(record::Dict{String, Any}, objfun, state, population,
                             method::Evolutionary.AbstractOptimizer, options)
    record["x"] = population
end

function __map_optimizer_args(prob::OptimizationProblem,
                              opt::Evolutionary.AbstractOptimizer;
                              callback = nothing,
                              maxiters::Union{Number, Nothing} = nothing,
                              maxtime::Union{Number, Nothing} = nothing,
                              abstol::Union{Number, Nothing} = nothing,
                              reltol::Union{Number, Nothing} = nothing,
                              kwargs...)
    mapped_args = (;kwargs...)

    if !isnothing(callback)
        mapped_args = (; mapped_args..., callback = callback)
    end

    if !isnothing(maxiters)
        mapped_args = (; mapped_args..., iterations = maxiters)
    end

    if !isnothing(maxtime)
        mapped_args = (; mapped_args..., time_limit = maxtime)
    end

    if !isnothing(abstol)
        mapped_args = (; mapped_args..., abstol = abstol)
    end

    if !isnothing(reltol)
        mapped_args = (; mapped_args..., reltol = reltol)
    end

    return Evolutionary.Options(; mapped_args...)
end

function SciMLBase.__solve(prob::OptimizationProblem, opt::Evolutionary.AbstractOptimizer,
                           data = Optimization.DEFAULT_DATA;
                           callback = (args...) -> (false),
                           maxiters::Union{Number, Nothing} = nothing,
                           maxtime::Union{Number, Nothing} = nothing,
                           abstol::Union{Number, Nothing} = nothing,
                           reltol::Union{Number, Nothing} = nothing,
                           progress = false, kwargs...)
    local x, cur, state

    if data != Optimization.DEFAULT_DATA
        maxiters = length(data)
    end

    cur, state = iterate(data)

    function _cb(trace)
        cb_call = callback(decompose_trace(trace).metadata["x"], trace.value...)
        if !(typeof(cb_call) <: Bool)
            error("The callback should return a boolean `halt` for whether to stop the optimization process.")
        end
        cur, state = iterate(data, state)
        cb_call
    end

    maxiters = Optimization._check_and_convert_maxiters(maxiters)
    maxtime = Optimization._check_and_convert_maxtime(maxtime)

    f = Optimization.instantiate_function(prob.f, prob.u0, prob.f.adtype, prob.p,
                                          prob.ucons === nothing ? 0 : length(prob.ucons))
    _loss = function (θ)
        x = prob.f(θ, prob.p, cur...)
        return first(x)
    end

    opt_args = __map_optimizer_args(prob, opt, callback = _cb, maxiters = maxiters,
                                    maxtime = maxtime, abstol = abstol, reltol = reltol;
                                    kwargs...)

    t0 = time()
    if isnothing(prob.lb) || isnothing(prob.ub)
        if !isnothing(f.cons)
            c = x -> (res = zeros(length(prob.lcons)); f.cons(res, x); res)
            cons = WorstFitnessConstraints(Float64[], Float64[], prob.lcons, prob.ucons, c)
            opt_res = Evolutionary.optimize(_loss, cons, prob.u0, opt, opt_args)
        else
            opt_res = Evolutionary.optimize(_loss, prob.u0, opt, opt_args)
        end
    else
        if !isnothing(f.cons)
            c = x -> (res = zeros(length(prob.lcons)); f.cons(res, x); res)
            cons = WorstFitnessConstraints(prob.lb, prob.ub, prob.lcons, prob.ucons, c)
        else
            cons = BoxConstraints(prob.lb, prob.ub)
        end
        opt_res = Evolutionary.optimize(_loss, cons, prob.u0, opt, opt_args)
    end
    t1 = time()
    opt_ret = Symbol(Evolutionary.converged(opt_res))

    SciMLBase.build_solution(SciMLBase.DefaultOptimizationCache(prob.f, prob.p), opt,
                             Evolutionary.minimizer(opt_res),
                             Evolutionary.minimum(opt_res); original = opt_res,
                             retcode = opt_ret, solve_time = t1 - t0)
end

end
