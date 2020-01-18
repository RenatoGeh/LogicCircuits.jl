#####################
# traversal infrastructure
#####################

@inline is⋀gate(n) = GateType(n) isa ⋀Gate
@inline is⋁gate(n) = GateType(n) isa ⋁Gate
@inline isliteralgate(n) = GateType(n) isa LiteralGate
@inline isconstantgate(n) = GateType(n) isa ConstantGate


import Base: foreach # extend

function foreach(node::DagNode, f_con::Function, f_lit::Function, f_a::Function, f_o::Function)
    f_leaf(n) = isliteralgate(n) ? f_lit(n) : f_con(n)
    f_inner(n) = is⋀gate(n) ? f_a(n) : f_o(n)
    foreach(node, f_leaf, f_inner)
    nothing # returning nothing helps save some allocations and time
end

import ..Utils: foldup # extend

"""
Compute a function bottom-up on the circuit. 
`f_con` is called on constant gates, `f_lit` is called on literal gates, 
`f_a` is called on conjunctions, and `f_o` is called on disjunctions.
Values of type `T` are passed up the circuit and given to `f_a` and `f_o` through a callback from the children.
"""
function foldup(node::ΔNode, f_con::Function, f_lit::Function, 
                f_a::Function, f_o::Function, ::Type{T})::T where {T}
    f_leaf(n) = isliteralgate(n) ? f_lit(n)::T : f_con(n)::T
    f_inner(n, call) = is⋀gate(n) ? f_a(n, call)::T : f_o(n, call)::T
    foldup(node, f_leaf, f_inner, T)
end

import ..Utils: foldup_aggregate # extend

"""
Compute a function bottom-up on the circuit. 
`f_con` is called on constant gates, `f_lit` is called on literal gates, 
`f_a` is called on conjunctions, and `f_o` is called on disjunctions.
Values of type `T` are passed up the circuit and given to `f_a` and `f_o` in an aggregate vector from the children.
"""
function foldup_aggregate(node::ΔNode, f_con::Function, f_lit::Function, 
                          f_a::Function, f_o::Function, ::Type{T})::T where T
    function f_leaf(n) 
        isliteralgate(n) ? f_lit(n)::T : f_con(n)::T
    end
    function f_inner(n, cs) 
        is⋀gate(n) ? f_a(n, cs)::T : f_o(n, cs)::T
    end
    foldup_aggregate(node, f_leaf::Function, f_inner::Function, T)
end

#####################
# traversal methods
#####################

"Get the list of conjunction nodes in a given circuit"
⋀_nodes(c::Union{ΔNode,Δ}) = filter(is⋀gate, c)

"Get the list of disjunction nodes in a given circuit"
⋁_nodes(c::Union{ΔNode,Δ}) = filter(is⋁gate, c)

"Number of variables in the circuit"
num_variables(c::Union{ΔNode,Δ}) = length(variable_scope(c))

"Get the probability that a random world satisties the circuit"
function sat_prob(circuit::Union{ΔNode,Δ})::Rational{BigInt}
    sat_prob(circuit, v -> BigInt(1) // BigInt(2))
end

function sat_prob(circuit::Δ, varprob::Function)::Rational{BigInt}
    sat_prob(circuit[end], varprob)
end

function sat_prob(root::ΔNode, varprob::Function)::Rational{BigInt}
    f_con(n) = is_true(n) ? one(Rational{BigInt}) : zero(Rational{BigInt})
    f_lit(n) = positive(n) ? varprob(variable(n)) : one(Rational{BigInt}) - varprob(variable(n))
    f_a(n, callback) = mapreduce(callback, *, children(n))
    f_o(n, callback) = mapreduce(callback, +, children(n))
    foldup(root, f_con, f_lit, f_a, f_o, Rational{BigInt})
end

"Get the model count of the circuit"
function model_count(circuit::Δ, num_vars_in_scope::Int = num_variables(circuit))::BigInt
    # note that num_vars_in_scope can be more than num_variables(circuit)
    BigInt(sat_prob(circuit) * BigInt(2)^num_vars_in_scope)
end

const Signature = Vector{Rational{BigInt}}

"Get a signature for each node using probabilistic equivalence checking"
function prob_equiv_signature(circuit::Δ, k::Int)::Dict{Union{Var,ΔNode},Signature}
    prob_equiv_signature(circuit[end],k)
end

function prob_equiv_signature(circuit::ΔNode, k::Int)::Dict{Union{Var,ΔNode},Signature}
    # uses probability instead of integers to circumvent smoothing, no mod though
    signs::Dict{Union{Var,ΔNode},Signature} = Dict{Union{Var,ΔNode},Signature}()
    prime::Int = 7919 #TODO set as smallest prime larger than num_variables
    randprob() = BigInt(1) .// rand(1:prime,k)
    do_signs(v::Var) = get!(randprob, signs, v)
    f_con(n) = (signs[n] = (is_true(n) ? ones(Rational{BigInt}, k) : zeros(Rational{BigInt}, k)))
    f_lit(n) = (signs[n] = (positive(n) ? do_signs(variable(n)) : BigInt(1) .- do_signs(variable(n))))
    f_a(n, call) = (signs[n] = (mapreduce(c -> call(c), (x,y) -> (x .* y), children(n))))
    f_o(n, call) = (signs[n] = (mapreduce(c -> call(c), (x,y) -> (x .+ y), children(n))))
    foldup(circuit, f_con, f_lit, f_a, f_o, Signature)
    signs
end

"Get the variable scope of the circuit node"
function variable_scope(circuit::Δ)::BitSet
    variable_scope(circuit[end])
end

function variable_scope(root::ΔNode)::BitSet
    f_con(n) = BitSet()
    f_lit(n) = BitSet(variable(n))
    f_inner(n, call) = mapreduce(call, union, children(n))
    foldup(root, f_con, f_lit, f_inner, f_inner, BitSet)
end

"Get the variable scope of each node in the circuit"
function variable_scopes(circuit::Δ)::Dict{ΔNode,BitSet}
    variable_scopes(circuit[end])
end

function variable_scopes(root::ΔNode)::Dict{ΔNode,BitSet}
    # variable_scopes(node2dag(root))
    scope = Dict{ΔNode,BitSet}()
    f_con(n) = scope[n] = BitSet()
    f_lit(n) = scope[n] = BitSet(variable(n))
    f_inner(n, call) = scope[n] = mapreduce(call, union, children(n))
    foldup(root, f_con, f_lit, f_inner, f_inner, BitSet)
    scope
end

"Is the circuit smooth?"
function is_smooth(circuit::Δ)::Bool
    is_smooth(circuit[end])
end

function is_smooth(root::ΔNode)::Bool
    result::Bool = true
    f_con(n) = BitSet()
    f_lit(n) = BitSet(variable(n))
    f_a(n, cs) = reduce(union, cs)
    f_o(n, cs) = begin
        scope = reduce(union, cs)
        result = result && all(c -> c == scope, cs)
        scope
    end 
    foldup_aggregate(root, f_con, f_lit, f_a, f_o, BitSet)
    result
end


"Is the circuit decomposable?"
function is_decomposable(circuit::Δ)::Bool
    is_decomposable(circuit[end])
end

function is_decomposable(root::ΔNode)::Bool
    result::Bool = true
    f_con(n) = BitSet()
    f_lit(n) = BitSet(variable(n))
    f_a(n, cs) = begin
        result = result && disjoint(cs...)
        reduce(union, cs)
    end 
    f_o(n, cs) = reduce(union, cs)
    foldup_aggregate(root, f_con, f_lit, f_a, f_o, BitSet)
    result
end

function smooth2(circuit::Δ)
    n = circuit[end]
    scope = variable_scopes(circuit)
    lit_nodes = literal_nodes(circuit, scope[n])
    
    f_con(n) = (n, BitSet())
    f_lit(n) = (n, BitSet(variable(n)))
    f_a(n, cv) = begin
        cn = first.(cv)
        cs = last.(cv)
        new_n = conjoin_like(n, cn...)
        new_scope = reduce(union, cs)
        (new_n, new_scope)
    end

    f_o(n, cv) = begin
        new_scope = reduce(union, last.(cv))
        parent_scope = new_scope

        # check if all missing_scopes is empty 
        # missing_scopes = map(cv) do (child, scope)
        #    setdiff(parent_scope, scope)
        # end
        
        # if all(map(missing_scopes) do s isempty(s) end)
        #    new_n = disjoin_like(n, first.(cv)...)
        #    return (new_n, new_scope)
        # end

        smoothed_children = map(cv) do (child, scope)
            missing_scope = setdiff(parent_scope, scope)
            smooth(child, missing_scope, lit_nodes)
            
            # do not catch literal nodes
            # if isempty(missing_scope)
            #    child
            # else
            #    ors = map(collect(missing_scope)) do v
            #        lit = var2lit(Var(v))
            #        disjoin_like(child, literal_like(n, lit), literal_like(n, -lit))
            #    end
            #    conjoin_like(child, child, ors...)
            # end

        end
        new_n = disjoin_like(n, smoothed_children...)
        (new_n, new_scope)
    end

    result = foldup_aggregate(n, f_con, f_lit, f_a, f_o, Tuple{ΔNode, BitSet})
    node2dag(first(result))
end

function smooth3(root::ΔNode)
    lit_nodes::Dict{Lit,ΔNode} = literal_nodes2(root)
    f_con(n) = (n, BitSet())
    f_lit(n) = (n, BitSet(variable(n)))
    f_a(n, cv) = begin
        new_n = conjoin_like(n, (first.(cv)))
        new_scope = mapreduce(last, union, cv)
        (new_n, new_scope)
    end
    f_o(n, cv) = begin
        new_scope = mapreduce(last, union, cv)
        smoothed_children = map(cv) do (child, scope)
            missing_scope = setdiff(new_scope, scope)
            smooth3(child, missing_scope, lit_nodes)
        end
        new_n = disjoin_like(n, smoothed_children)
        (new_n, new_scope)
    end
    (smoothed_root, _) = foldup_aggregate(root, f_con, f_lit, f_a, f_o, Tuple{ΔNode, BitSet})
    smoothed_root
end

function smooth4(root::ΔNode)
    lit_nodes::Dict{Lit,ΔNode} = literal_nodes2(root)
    scopes::Dict{ΔNode,BitSet} = variable_scopes(root)
    f_same(n) = n
    f_a(n, call) = conjoin_like(n, map(call, children(n))...)
    f_o(n, call) = begin
        parent_scope = scopes[n]
        smoothed_children = map(children(n)) do child
            scope = scopes[child]
            smooth_child = call(child)
            missing_scope = setdiff(parent_scope, scope)
            smooth3(smooth_child, missing_scope, lit_nodes)
        end
        disjoin_like(n, smoothed_children...)
    end
    foldup(root, f_same, f_same, f_a, f_o, ΔNode)
end

#TODO is it faster to know the type of ΔNode more specifically?
function smooth5(root::ΔNode)
    lit_nodes::Dict{Lit,ΔNode} = literal_nodes2(root)
    f_con(n) = (n, BitSet(), false)
    f_lit(n) = (n, BitSet(variable(n)), false)
    f_a(n, call) = begin
        smooth_children = Vector{ΔNode}()
        new_scope = BitSet()
        new_changed = false
        for child in children(n)
            (smooth_child, scope, changed) = call(child)
            push!(smooth_children,smooth_child)
            union!(new_scope,scope)
            new_changed = changed || new_changed
        end
        new_n = new_changed ? conjoin_like(n, smooth_children) : n
        (new_n, new_scope, new_changed)
    end
    f_o(n, call) = begin
        smooth_children = Vector{ΔNode}()
        new_scope = BitSet()
        new_changed = false
        for child in children(n)
            (_, scope, changed) = call(child)
            union!(new_scope,scope)
            new_changed = changed || new_changed
        end
        for child in children(n)
            (smooth_child, scope, _) = call(child)
            missing_scope = setdiff(new_scope, scope)
            smooth_child = smooth3(smooth_child, missing_scope, lit_nodes)
            push!(smooth_children,smooth_child)
            new_changed = new_changed || !isempty(missing_scope)
        end
        if !new_changed
            return (n, new_scope, new_changed)
        else
            return (disjoin_like(n, smooth_children), new_scope, new_changed)
        end
    end
    (smoothed_root, _, _) = foldup(root, f_con, f_lit, f_a, f_o, Tuple{ΔNode, BitSet, Bool})
    smoothed_root
end

"Make the circuit smooth"
function smooth(circuit::Δ)
    scope = variable_scopes(circuit)
    lit_nodes = literal_nodes(circuit, scope[circuit[end]])
    smoothed = Dict{ΔNode,ΔNode}()
    smooth_node(n::ΔNode) = smooth_node(GateType(n),n)
    smooth_node(::LeafGate, n::ΔNode) = n
    function smooth_node(::⋀Gate, n::ΔNode)
        smoothed_children = map(c -> smoothed[c], children(n))
        conjoin_like(n, smoothed_children...)
    end
    function smooth_node(::⋁Gate, n::ΔNode) 
        parent_scope = scope[n]
        smoothed_children = map(children(n)) do c
            missing_scope = setdiff(parent_scope, scope[c])
            smooth(smoothed[c], missing_scope, lit_nodes)
        end
        disjoin_like(n, smoothed_children...)
    end
    for node in circuit
        smoothed[node] = smooth_node(node)
    end
    node2dag(smoothed[circuit[end]])
end

"Return a smooth version of the node where the missing variables are added to the scope"
function smooth(node::ΔNode, missing_scope, lit_nodes)
    if isempty(missing_scope)
        return node
    else
        ors = map(collect(missing_scope)) do v
            lit = var2lit(Var(v))
            disjoin_like(node, lit_nodes[lit], lit_nodes[-lit])
        end
        return conjoin_like(node, node, ors...)
    end
end


"Return a smooth version of the node where the missing variables are added to the scope"
function smooth3(node::ΔNode, missing_scope, lit_nodes)
    if isempty(missing_scope)
        return node
    else
        ors = map(collect(missing_scope)) do v
            lit = var2lit(Var(v))
            lit_node = get!(lit_nodes, lit) do 
                literal_like(root[end], lit)
            end
            not_lit_node = get!(lit_nodes, -lit) do 
                literal_like(root[end], -lit)
            end
            disjoin_like(node, lit_node, not_lit_node)
        end
        return conjoin_like(node, node, ors...)
    end
end

"""
Forget variables from the circuit. 
Warning: this may or may not destroy the determinism property.
"""
function forget(is_forgotten::Function, circuit::Δ)
    forgotten = Dict{ΔNode,ΔNode}()
    (_, true_node) = constant_nodes(circuit) # reuse constants when possible
    if isnothing(true_node)
        true_node = true_like(circuit[end])
    end
    forget_node(n::ΔNode) = forget_node(GateType(n),n)
    forget_node(::ConstantGate, n::ΔNode) = n
    forget_node(::LiteralGate, n::ΔNode) =
        is_forgotten(variable(n)) ? true_node : n
    function forget_node(::⋀Gate, n::ΔNode)
        forgotten_children = map(c -> forgotten[c], children(n))
        conjoin_like(n, forgotten_children...)
    end
    function forget_node(::⋁Gate, n::ΔNode) 
        forgotten_children = map(c -> forgotten[c], children(n))
        disjoin_like(n, forgotten_children...)
    end
    for node in circuit
        forgotten[node] = forget_node(node)
    end
    node2dag(forgotten[circuit[end]])
end

"Remove all constant leafs from the circuit"
function propagate_constants(circuit::Δ)
    proped = Dict{ΔNode,ΔNode}()
    propagate(n::ΔNode) = propagate(GateType(n),n)
    propagate(::LeafGate, n::ΔNode) = n
    function propagate(::⋀Gate, n::ΔNode) 
        proped_children = map(c -> proped[c], children(n))
        if any(c -> is_false(c), proped_children)
            false_like(n) 
        else
            proped_children = filter(c -> !is_true(c), proped_children)
            conjoin_like(n, proped_children...)
        end
    end
    function propagate(::⋁Gate, n::ΔNode) 
        proped_children = map(c -> proped[c], children(n))
        if any(c -> is_true(c), proped_children)
            true_like(n) 
        else
            proped_children = filter(c -> !is_false(c), proped_children)
            disjoin_like(n, proped_children...)
        end
    end
    for node in circuit
        proped[node] = propagate(node)
    end
    node2dag(proped[circuit[end]])
end


"Construct a mapping from literals to their canonical node representation"
function literal_nodes(circuit::Δ, scope::BitSet = variable_scope(circuit))::Dict{Lit,ΔNode}
    repr = Dict{Lit,ΔNode}()
    repr_node(n::ΔNode) = repr_node(GateType(n),n)
    repr_node(::GateType, n::ΔNode) = ()
    repr_node(::LiteralGate, n::ΔNode) = begin
        if haskey(repr, literal(n))
            error("Circuit has multiple representations of literal $(literal(n))")
        end
        repr[literal(n)] = n
    end
    for node in circuit
        repr_node(node)
    end
    for vint in scope
        v = var(vint)
        if !haskey(repr, var2lit(v))
            repr[var2lit(v)] = literal_like(circuit[end], var2lit(v))
        end
        if !haskey(repr, -var2lit(v)) 
            repr[-var2lit(v)] = literal_like(circuit[end], -var2lit(v))
        end
    end
    repr
end

"Construct a mapping from literals to their canonical node representation"
function literal_nodes2(circuit::Union{Δ,ΔNode})::Dict{Lit,ΔNode}
    lit_dict = Dict{Lit,ΔNode}()
    foreach(circuit) do n
        if isliteralgate(n)
            if haskey(lit_dict, literal(n))
                error("Circuit has multiple representations of literal $(literal(n))")
            end
            lit_dict[literal(n)] = n
        end
    end
    lit_dict
end

"Construct a mapping from constants to their canonical node representation"
function constant_nodes(circuit::Δ)::Tuple{ΔNode,ΔNode}
    true_node = nothing
    false_node = nothing
    visit(n::ΔNode) = visit(GateType(n),n)
    visit(::GateType, n::ΔNode) = ()
    visit(::ConstantGate, n::ΔNode) = begin
        if is_true(n)
            if issomething(true_node) 
                error("Circuit has multiple representations of true")
            end
            true_node = n
        else
            @assert is_false(n)
            if issomething(false_node) 
                error("Circuit has multiple representations of false")
            end
            false_node = n
        end
    end
    for node in circuit
        visit(node)
    end
    (false_node, true_node)
end

"Check whether literal nodes are unique"
function has_unique_literal_nodes(circuit::Δ)::Bool
    literals = Set{Lit}()
    result = true
    visit(n::ΔNode) = visit(GateType(n),n)
    visit(::GateType, n::ΔNode) = ()
    visit(::LiteralGate, n::ΔNode) = begin
        if literal(n) ∈ literals 
            result = false
        end
        push!(literals, literal(n))
    end
    for node in circuit
        visit(node)
    end
    return result
end

"Check whether constant nodes are unique"
function has_unique_constant_nodes(circuit::Δ)::Bool
    seen_false = false
    seen_true = false
    result = true
    visit(n::ΔNode) = visit(GateType(n),n)
    visit(::GateType, n::ΔNode) = ()
    visit(::ConstantGate, n::ΔNode) = begin
        if is_true(n)
            if seen_true 
                result = false
            end
            seen_true = true
        else
            @assert is_false(n)
            if seen_false 
                result = false
            end
            seen_false = true
        end
    end
    for node in circuit
        visit(node)
    end
    return result
end