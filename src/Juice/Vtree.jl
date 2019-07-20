#############
# Vtree
#############

"Root of the vtree node hiearchy"
abstract type VtreeNode end

struct VtreeLeafNode <: VtreeNode
    index::UInt32
    var::Var
end

struct VtreeInnerNode <: VtreeNode
    index::UInt32
    left::VtreeNode
    right::VtreeNode
    var_count::Int
    variables::Set{Var}
end

#####################
# Constructor
#####################

IsLeaf(n::VtreeLeafNode) = true
IsLeaf(n::VtreeInnerNode) = false

Variables(n::VtreeLeafNode) = Set([n.var])
Variables(n::VtreeInnerNode) = n.variables

VariableCount(n::VtreeLeafNode) = 1
VariableCount(n::VtreeInnerNode) = n.var_count

"""
Returns the nodes in order of leaves to root.
Which is basically reverse Breadth First Search from the root.
"""
function OrderNodesLeavesBeforeParents(root::VtreeNode)::Vector{VtreeNode}
    # Running BFS
    visited = Vector{VtreeNode}()
    visited_idx = 0
    push!(visited, root)

    while visited_idx < length(visited)
        visited_idx += 1
        
        if visited[visited_idx] isa VtreeLeafNode
            
        else
            left = visited[visited_idx].left
            right = visited[visited_idx].right
            
            push!(visited, right)
            push!(visited, left)
        end
    end

    reverse(visited)
end


const VTREE_FORMAT = """c ids of vtree nodes start at 0
c ids of variables start at 1
c vtree nodes appear bottom-up, children before parents
c
c file syntax:
c vtree number-of-nodes-in-vtree
c L id-of-leaf-vtree-node id-of-variable
c I id-of-internal-vtree-node id-of-left-child id-of-right-child
c
"""

"""
Saves a vtree in the given file path.
"""
function save(vtree::Vector{VtreeNode}, file::AbstractString)
    open(file, "w") do f
        order = OrderNodesLeavesBeforeParents(vtree[end]);
        vtree_count = length(vtree)

        write(f, VTREE_FORMAT)
        
        write(f, "vtree $vtree_count\n")
        for (ind, node) in enumerate(order)
            if node isa VtreeLeafNode
                node_index = node.index
                node_variable = node.var
                write(f, "L $node_index $node_variable\n")
            elseif node isa VtreeInnerNode
                node_index = node.index
                left = node.left.index
                right = node.right.index
                write(f, "I $node_index $left $right\n")
            else
                throw("Invalid Vtree Node Type")
            end
        end
    end
end