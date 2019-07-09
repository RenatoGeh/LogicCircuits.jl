#####################
# Aggregate flow circuits
# (like a flow circuit but aggregates flows over several examples and batches)
#####################

abstract type AggregateFlowCircuitNode{A} <: CircuitNode end
abstract type AggregateFlowLeafNode{A} <: AggregateFlowCircuitNode{A} end
abstract type AggregateFlowInnerNode{A} <: AggregateFlowCircuitNode{A} end

struct AggregateFlowPosLeaf{A} <: AggregateFlowLeafNode{A}
    origin::CircuitNode
end

struct AggregateFlowNegLeaf{A} <: AggregateFlowLeafNode{A}
    origin::CircuitNode
end

struct AggregateFlow⋀{A} <: AggregateFlowInnerNode{A}
    origin::CircuitNode
    children::Vector{<:AggregateFlowCircuitNode{A}}
end

mutable struct AggregateFlow⋁{A} <: AggregateFlowInnerNode{A}
    origin::CircuitNode
    children::Vector{<:AggregateFlowCircuitNode{A}}
    aggr_flow::A
    aggr_flow_children::Vector{A}
end

const AggregateFlowCircuit△{A} = AbstractVector{<:AggregateFlowCircuitNode{A}}

#####################
# traits
#####################

@traitimpl Leaf{AggregateFlowLeafNode}
@traitimpl Inner{AggregateFlowInnerNode}
@traitimpl Circuit△{AggregateFlowCircuit△}

NodeType(::Type{<:AggregateFlowPosLeaf}) = PosLeaf()
NodeType(::Type{<:AggregateFlowNegLeaf}) = NegLeaf()

NodeType(::Type{<:AggregateFlow⋀}) = ⋀()
NodeType(::Type{<:AggregateFlow⋁}) = ⋁()

#####################
# constructors and conversions
#####################

const AggregateFlowCache = Dict{CircuitNode, AggregateFlowCircuitNode}

AggregateFlowCircuitNode(n::CircuitNode, ::Type{A}, cache::AggregateFlowCache) where A =
    AggregateFlowCircuitNode(NodeType(n), n, A, cache)

AggregateFlowCircuitNode(nt::PosLeaf, n::CircuitNode, ::Type{A}, cache::AggregateFlowCache) where A =
    get!(()-> AggregateFlowPosLeaf{A}(n), cache, n)

AggregateFlowCircuitNode(nt::NegLeaf, n::CircuitNode, ::Type{A}, cache::AggregateFlowCache) where A =
    get!(()-> AggregateFlowNegLeaf{A}(n), cache, n)

AggregateFlowCircuitNode(nt::⋀, n::CircuitNode, ::Type{A}, cache::AggregateFlowCache) where A =
    get!(cache, n) do
        AggregateFlow⋀(n, AggregateFlowCircuit(n.children, A, cache))
    end

AggregateFlowCircuitNode(nt::⋁, n::CircuitNode, ::Type{A}, cache::AggregateFlowCache) where A =
    get!(cache, n) do
        AggregateFlow⋁(n, AggregateFlowCircuit(n.children, A, cache), zero(A), some_vector(A, num_children(n)))
    end

@traitfn function AggregateFlowCircuit(c::C, ::Type{A}, cache::AggregateFlowCache = AggregateFlowCache()) where {A, C; Circuit△{C}}
    map(n->AggregateFlowCircuitNode(n, A, cache), c)
end

#####################
# methods
#####################

@inline cvar(n::AggregateFlowLeafNode)::Var  = cvar(n.origin)

function collect_aggr_flows(afc::AggregateFlowCircuit△, batches::XBatches{Bool})
    for n in afc
        # set flow counters to zero
        reset_aggregate_flow(n)
    end
    opts = (flow_opts★..., el_type=Bool, compact⋁=false) #keep default options but insist on Bool flows
    fc = FlowCircuit(afc, max_batch_size(batches), Bool, FlowCache(), opts)
    for batch in batches
        collect_aggr_flows_batch(fc, batch)
    end
end

reset_aggregate_flow(::AggregateFlowCircuitNode) = () # do nothing
reset_aggregate_flow(n::AggregateFlow⋁{A}) where A = (n.aggr_flow = zero(A) ; n.aggr_flow_children .= zero(A))

function collect_aggr_flows_batch(fc::FlowCircuit△, batch::XData{Bool})
    # pass a mini-batch through the flow circuit
    pass_up_down(fc, plain_x_data(batch))
    for n in fc
         # collect flows from mini-batch into aggregate statistics
        aggregate_flow(n, batch)
    end
end

aggregate_flow(::FlowCircuitNode, ::Any) = () # do nothing
function aggregate_flow(n::Flow⋁, xd::XData{Bool})
    origin = n.origin::AggregateFlow⋁
    origin.aggr_flow += count(π(n))
    if num_children(n) == 1
        # flow goes entirely to one child
        origin.aggr_flow_children[1] += aggregate_data(xd,π(n))
    else
        child_aggr_flows = map(n.children) do c
            pr_fs = pr_factors(c)
            aggregate_data_factorized(xd, π(n), pr_fs...)
        end
        origin.aggr_flow_children .+= child_aggr_flows
    end
end

aggregate_data(xd::PlainXData, f::AbstractArray) = sum(f)
aggregate_data(xd::PlainXData, f::AbstractArray{Bool}) = count(f)
aggregate_data(xd::WXData, f::AbstractArray) = sum(f .* weights(xd))

aggregate_data_factorized(xd::PlainXData, x1::BitVector, xs::BitVector...) = count_conjunction(x1, xs...)
aggregate_data_factorized(xd::WXData, x1::BitVector, xs::BitVector...) = sum_weighted_conjunction(weights(xd), x1, xs)