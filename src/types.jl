#= "second class" data types employed by singular

#### Tuples

The only way to construct a tuple in singular is via the syntax
    a, b, c
Tuples are also called expression lists in the singular grammar/documentation.
There are no variables of type tuple.

#### Nothing

There are many different kinds of nothing in Singular with distinct behaviours,
but we conflate them all into the single Julia nothing and hope for the best.

First, it is possible for elements of a Singular list to be nothing: l[1] after
    list l; l[2] = 0;

Second, functions can also return "nothing": the return value of
    proc f() {return();};

Third, variables declared "def" in Singular start out with a value of nothing.

There may be more nothings in Singular...

All of these nothings are distinct from a zero-length tuple and are very distinct
from the SName type defined below: the statement
    a, b = 1, f(), 1;
fails in the Singular interpreter because the right hand side has length 3. The statement
    a, b, c = 1, f(), 1;
fails in the Singular interpreter because something on the "right side is not a datum".

The Julia interpreter will fail in the first example because the length of the rhs tuple is checked before assignment.
The Julia interpreter will fail in the second example because the assignment to b is done via
    b = convert2T(..)       # T is the stored type of b
and the convert2T will throw an error on :nothing (unless b is nothing, where T would behave like def)

In general, it is allowed to pass nothing around in singular:
list k, l;
l[2] = 0;       // size(l) is 2, l[1] is nothing
k[1] = 0;       // size(k) is 1
k[1] = l[1];    // size(k) is 0

Therefore, the error must occur when trying to assign nothing to b, and not when constructing the tuple.

#### Names

The four letters in the singular code
    a = f(b, c);
start out life as names SName(:a), SName(:f), ect.
When needed, the names are looked up at runtime via a function called make.

Due to a bug in the current c singular, we can see what the interpreter thinks the type of these names is:
> proc f() {return(1,x)};
> typeof(f());
int ?unknown type?

There are no variables of type name.

=#

####################### types unavailable to the user ###########################

#### singular type expression list
# note: expression lists cannot have expression lists as elements: everything is
#       always auto splatted. Like the list type SListData below, elements
#       of an STuple must own their data. Hence, for example, no element should
#       have type Array{Int, 2}, but rather SIntMat.
struct STuple
    list::Vector{Any}
end

#### singular type nothing
# Nothing same

#### singular type ?unknown type?
# TODO possible make this the same as Symbol. makeunknown would become a quote
struct SName
    name::Symbol
end
makeunknown(s::String) = SName(Symbol(s))

show(io::IO, a::SName) = print(io, ":"*string(a.name))


########################## ring independent types #############################

##### singular type "proc"      immutable in the singular language
struct SProc
    func::Function
    name::String
    package::Symbol
end
procname_to_func(name::String) = Symbol("##"*name)
procname_to_func(f::Symbol) = procname_to_func(f.name)


#### singular type "int"        immutable in the singular language
# Int same


#### singular type "bigint"     immutable in the singular language
# BigInt same


#### singular type "string"     immutable in the singular language
# Singular splats all arguments inside () by default, so we need ... in Julia
# The julia String is iterable, so we need another type
struct SString
    string::String
end


#### singular type "intvec"     mutable in the singular language
struct SIntVec
    vector::Vector{Int}
end


#### singular type "intmat"     mutable in the singular language
struct SIntMat
    matrix::Array{Int, 2}
end


#### singular type "bigintmat"  mutable in the singular language
struct SBigIntMat
    matrix::Array{BigInt, 2}
end


#### singular type "ring"       immutable in the singular language, but also holds identifiers of ring-dependent types
mutable struct SRing
    ring_ptr::libSingular.ring
    refcount::Int
    level::Int                  # 1->created at global, 2->created in fxn called from global, ect..
    vars::Dict{Symbol, Any}     # global ring vars
    valid::Bool                 # valid==false <=> ring_ptr==NULL

    function SRing(valid_::Bool, ring_ptr_::libSingular.ring, level::Int)
        r = new(ring_ptr_, 1, level, Dict{Symbol, Any}(), valid_)
        finalizer(rt_ring_finalizer, r)
        return r
    end
end

function rt_ring_finalizer(a::SRing)
    a.refcount -= 1
    if a.refcount <= 0
        @assert a.refcount == 0
        libSingular.rDelete(a.ring_ptr)
    end
end


#### singular type "list"       mutable in the singular language
# note: Lists can have anything in them - including polynomials from different
#       rings. The parent, ring_dep_count, and back members are for maintaining
#       compatibility with backwards singular, where the content of a list can
#       change the location of its name.
#       The integrity of this structure can be checked with object_is_ok
mutable struct SListData
    data::Vector{Any}
    parent::SRing           # parent.valid <=> list is considered ring dependent
    ring_dep_count::Int     # count of ring dependent elements
    back::Any               # pointer to data that possibly needs changing when ring dependence changes
end

struct SList
    list::SListData
end


############################ ring dependent types ############################
# The constructor for T takes ownership of a raw pointer and stores in the member T_ptr

#### singular type "number"     immutable in the singular language
mutable struct SNumber
    number_ptr::libSingular.number
    parent::SRing

    function SNumber(number_ptr_::libSingular.number, parent_::SRing)
        a = new(number_ptr_, parent_)
        finalizer(rt_number_finalizer, a)
        parent_.refcount += 1
        @assert parent_.refcount > 1
        return a
    end
end

function rt_number_finalizer(a::SNumber)
    libSingular.n_Delete(a.number_ptr, a.parent.ring_ptr)
    rt_ring_finalizer(a.parent)
end


#### singular type "poly"       immutable in the singular language
mutable struct SPoly
    poly_ptr::libSingular.poly
    parent::SRing

    function SPoly(poly_ptr_::libSingular.poly, parent_::SRing)
        a = new(poly_ptr_, parent_)
        finalizer(rt_poly_finalizer, a)
        parent_.refcount += 1
        @assert parent_.refcount > 1
        return a
    end
end

sing_ring(p::SPoly) = p.parent
sing_ptr(p::SPoly) = p.poly_ptr

function rt_poly_finalizer(a::SPoly)
    libSingular.p_Delete(a.poly_ptr, a.parent.ring_ptr)
    rt_ring_finalizer(a.parent)
end


#### singular type "ideal"      mutable like a list in the singular language
mutable struct SIdealData
    ideal_ptr::libSingular.ideal
    parent::SRing

    function SIdealData(ideal_ptr_::libSingular.ideal, parent_::SRing)
        a = new(ideal_ptr_, parent_)
        finalizer(rt_ideal_finalizer, a)
        parent_.refcount += 1
        @assert parent_.refcount > 1
        return a
    end
end

sing_ptr(i::SIdealData) = i.ideal_ptr
sing_ring(i::SIdealData) = i.parent

function rt_ideal_finalizer(a::SIdealData)
    libSingular.id_Delete(a.ideal_ptr, a.parent.ring_ptr)
    rt_ring_finalizer(a.parent)
end

struct SIdeal
    ideal::SIdealData
end

sing_ptr(i::SIdeal) = sing_ptr(i.ideal)
sing_ring(i::SIdeal) = sing_ring(i.ideal)

#### singular type "matrix"
mutable struct SMatrix
#    value::libSingular.matrix
    parent::SRing
end


# the underscore types include the underlying mutable containers
const _IntVec    = Union{SIntVec, Vector{Int}}
const _IntMat    = Union{SIntMat, Array{Int, 2}}
const _BigIntMat = Union{SBigIntMat, Array{BigInt, 2}}
const _List      = Union{SList, SListData}
const _Ideal     = Union{SIdeal, SIdealData}

# it is almost useless to have a list of singular types because of newstruct
#const SingularType = Union{Nothing, SProc, Int, BigInt, SString,
#                           SIntVec, SIntMat, SBigIntMat, SList,
#                           SRing, SNumber, SPoly, SIdeal}

# the set of possible ring dependent types is finite because newstruct creates ring indep types
# all ring dependent types have a .parent member for the ring
const SingularRingType = Union{SList, SNumber, SPoly, SIdeal}

# the types that are always ring dependent
const _SingularRingType = Union{SNumber, SPoly, SIdeal, SIdealData}

# this function is broken now
function type_is_ring_dependent(t::String)
    return t == "number" || t == "poly" || t == "ideal" || t == "matrix"
end


#const _SingularType = Union{SingularType,
#                           Vector{Int}, Array{Int, 2}, Array{BigInt, 2}, SListData,
#                           SIdealData}


########################## transpiler types ###################################

struct AstNode
    rule::Int32
    child::Vector{Any}
end

function AstNodeMake(h, l...)
    return AstNode(h, [l...])
end

struct TranspileError <: Exception
    name::String
end

Base.showerror(io::IO, er::TranspileError) = print(io, "transpilation error: ", er.name)

mutable struct AstEnv
    package::Symbol
    fxn_name::String
    ok_to_branchto::Bool    # is cmd branchTo allowed?
    branchto_appeared::Bool # have we seen a branchTo yet?
    ok_to_return::Bool      # is return allowed?
    at_top::Bool
    everything_is_screwed::Bool                 # no local variables may go into local storage
    rings_are_screwed::Bool                     # no local ring dependent variables may go into local storage
    appeared_identifiers::Dict{String, Int}     # name => some data
    declared_identifiers::Dict{String, String}  # name => type
end

mutable struct AstLoadEnv
    export_names::Bool
    package::Symbol
end


######################## runtime global state #################################

# The CallStackEntry holds the "context" required by every function.
# This could be passed around as a first argument to _every_ rt function, but
# we take the simpler approach for now and manually manage a call stack in rtGlobal.callstack.
mutable struct rtCallStackEntry
#=
    Should always have
        start_all_locals <= start_current_locals <= length(rtGlobal.local_vars) + 1

    Variables in [start_current_locals, length(rtGlobal.local_vars)] are our
    local vars, including the ring independent vars and the ring dependent
    vars from the current ring.

    Variables in [start_all_locals, start_current_locals) are our hidden local
    ring dependent vars. They are hidden by the fact that their ring is not
    the current ring.

    Obviously, this makes changing the current ring inside a function an
    expensive operation that involves rearranging the whole interval
        [start_all_locals, length(rtGlobal.local_vars)]
    and setting start_current_locals appropriately.
=#
    start_all_locals::Int       # index into rtGlobal.local_vars
    start_current_locals::Int   # index into rtGlobal.local_vars
    current_ring::SRing
    current_package::Symbol
end

mutable struct rtGlobalState
    SearchPath::Vector{String}
    optimize_locals::Bool
    last_printed::Any
    rtimer_base::UInt64
    rtimer_scale::UInt64
    vars::Dict{Symbol, Dict{Symbol, Any}}     # global ring indep vars
    callstack::Array{rtCallStackEntry}
    local_vars::Array{Pair{Symbol, Any}}
    newstruct_casts::Dict{String, Function}   # available newstruct's and their cast operators
end

# when there is no current ring, the current ring is "invalid"
const rtInvalidRing = SRing(false, libSingular.rDefault_null_helper(), 1)

const rtGlobal = rtGlobalState(String[],
                               false,
                               nothing,
                               time_ns(),
                               1000000000,
                               Dict(:Top => Dict{Symbol, Any}()),
                               rtCallStackEntry[rtCallStackEntry(1, 1, rtInvalidRing, :Top)],
                               Pair{Symbol, Any}[],
                               Dict{String, Function}())

const empty_tuple = STuple(Any[])

function reset_runtime()
    rtGlobal.optimize_locals = false
    rtGlobal.last_printed = nothing
    rtGlobal.rtimer_base = time_ns()
    rtGlobal.rtimer_scale = 1000000000
    rtGlobal.vars = Dict(:Top => Dict{Symbol, Any}())
    rtGlobal.callstack = rtCallStackEntry[rtCallStackEntry(1, 1, rtInvalidRing, :Top)]
    rtGlobal.local_vars = Pair{Symbol, Any}[]
    rtGlobal.newstruct_casts = Dict{String, Function}()
end


###### these macros do not work without esc !!!!

macro warn_check(cond, msg)
    return :($(esc(cond)) ? nothing : rt_warn($(esc(msg))))
end

macro error_check(cond, msg)
    return :($(esc(cond)) ? nothing : rt_error($(esc(msg))))
end

macro expensive_assert(cond)
    return nothing
#    return :($(esc(cond)) ? nothing : rt_error("expensive assertion failed"))
end
