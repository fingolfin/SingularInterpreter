##################### the lazy way: use sleftv's ##########
using .libSingular: Sleftv


rChangeCurrRing(r::Sring) = libSingular.rChangeCurrRing(r.value)

function rChangeCurrRing(r::Ptr{Cvoid})
    @assert r == C_NULL
    libSingular.rChangeCurrRing(libSingular.rDefault_null_helper())
end

_copy(x::Sring) = libSingular.rCopy(x.value)
_copy(x::Union{Spoly,Svector}) = libSingular.p_Copy(x.value, x.parent.value)
_copy(x::Sideal) = libSingular.id_Copy(x.value, x.parent.value)
_copy(x::Smatrix) = libSingular.mp_Copy(x.value, x.parent.value)
_copy(x::Snumber) = libSingular.n_Copy(x.value, x.parent.value)


### sleftv ###

function Base.getproperty(lv::Sleftv, name::Symbol)
    if name == :next
        libSingular.sleftv_next(lv)
    elseif name == :data
        libSingular.sleftv_data(lv)
    elseif name == :rtyp
        libSingular.sleftv_type(lv)
    elseif name == :Init
        () -> libSingular.sleftv_init(lv)
    elseif name == :cpp_object
        getfield(lv, :cpp_object)
    else
        error("type Sleftv has not field $name")
    end
end

function Base.setproperty!(lv::Sleftv, name::Symbol, x)
    if name == :next
        libSingular.sleftv_next(lv, x)
    elseif name == :data
        libSingular.sleftv_data(lv, x)
    elseif name == :rtyp
        libSingular.sleftv_type(lv, x)
    else
        error("type Sleftv has not field $name")
    end
end

Base.propertynames(lv::Sleftv, private=false) = (:next, :data, :rtyp, :Init, :cpp_object)

function lv_init!(lv::Sleftv, typ, data)
    lv.Init()
    lv.rtyp = Cint(typ)
    lv.data = data
end

const _sleftvs = Sleftv[]
const _MAX_ARGS = 3

function get_sleftv(i::Int)
    if isempty(_sleftvs)
        for i=1:_MAX_ARGS+1
            push!(_sleftvs, Sleftv())
        end
    end
    _sleftvs[i+1]
end


### set_arg ###

set_arg(lv, x::Int; kw...) = lv_init!(lv, INT_CMD, Ptr{Cvoid}(x))

function set_arg(lv, x::BigInt; withcopy=false, withname=false)
    n = GC.@preserve x libSingular.n_InitMPZ_internal(pointer_from_objref(x),
                                                      libSingular.coeffs_BIGINT())
    lv_init!(lv, BIGINT_CMD, n.cpp_object)
end

function set_arg(lv, x::Union{Spoly,Svector,Sideal,Smatrix,Snumber,Sring}; withcopy=true, withname=false)
    val = withcopy ? _copy(x) : x.value
    lv_init!(lv, type_id(typeof(x)), val.cpp_object)
end

function set_arg(lv, x::Sstring; withcopy=false, withname=false)
    libSingular.set_sleftv_string(lv, x.value, withname)
end

function set_arg(lv, x::Union{Sintvec, Sintmat}; withcopy=false, withname=false)
    x = x.value
    libSingular.set_sleftv_intvec(lv, vec(x), x isa Matrix, size(x, 1), size(x, 2))
end

function set_arg(lv, x::Sbigintmat; withcopy=false, withname=false)
    a = Array{Any}(x.value) # TODO: optimize this method to avoid copying
    GC.@preserve a libSingular.set_sleftv_bigintmat(lv, vec(a), size(a, 1), size(a, 2))
end

function set_arg(lv, x::Slist; kwargs...)
    m::Sleftv = libSingular.set_sleftv_list(lv, length(x.value))
    # m is in fact the first element of an array,
    # sleftv_at below allows to reach subsequent elements
    for (i, elt) in enumerate(x.value)
        set_arg(libSingular.sleftv_at(m, i - 1), elt, withcopy=true)
    end
end

set_arg1(x; withcopy=false, withname=false) =
    set_arg(get_sleftv(1), x; withcopy=withcopy, withname=withname)

set_arg2(x; withcopy=false, withname=false) =
    set_arg(get_sleftv(2), x; withcopy=withcopy, withname=withname)

set_arg3(x; withcopy=false, withname=false) =
    set_arg(get_sleftv(3), x; withcopy=withcopy, withname=withname)


### get_res ###

function get_res(expectedtype::CMDS)
    res = get_sleftv(0)
    @assert res.next.cpp_object == C_NULL
    @assert res.rtyp == Int(expectedtype)
    res.data
end

function get_res(::Type{Any})
    res = get_sleftv(0)
    @assert res.next.cpp_object == C_NULL # TODO: handle when it's a tuple!
    get_res(convertible_types[CMDS(res.rtyp)], res.data)
end

get_res(::Type{Int}, data=get_res(INT_CMD)) = Int(data)

function get_res(::Type{BigInt}, data=get_res(BIGINT_CMD))
    d = Int(data)
    if d & 1 != 0 # immediate int
        BigInt(d >> 2)
    else
        Base.GMP.MPZ.set(unsafe_load(Ptr{BigInt}(data))) # makes a copy of internals
    end
end

get_res(::Type{Spoly}, data=get_res(POLY_CMD)) =
    Spoly(libSingular.internal_void_to_poly_helper(data), rt_basering())

get_res(::Type{Svector}, data=get_res(VECTOR_CMD)) =
    Svector(libSingular.internal_void_to_poly_helper(data), rt_basering())

get_res(::Type{Snumber}, data=get_res(NUMBER_CMD)) =
    Snumber(libSingular.internal_void_to_number_helper(data), rt_basering())

get_res(::Type{Sideal}, data=get_res(IDEAL_CMD)) =
    Sideal(libSingular.internal_void_to_ideal_helper(data), rt_basering(), true)

get_res(::Type{Smatrix}, data=get_res(MATRIX_CMD)) =
    Smatrix(libSingular.internal_void_to_matrix_helper(data), rt_basering(), true)

function get_res(::Type{Sintvec}, data=get_res(INTVEC_CMD))
    d = libSingular.lvres_array_get_dims(data, Int(INTVEC_CMD))[1]
    iv = Vector{Int}(undef, d)
    libSingular.lvres_to_jlarray(iv, data, Int(INTVEC_CMD))
    Sintvec(iv, true)
end

function get_res(::Type{Sintmat}, data=get_res(INTMAT_CMD))
    d = libSingular.lvres_array_get_dims(data, Int(INTMAT_CMD))
    im = Matrix{Int}(undef, d)
    libSingular.lvres_to_jlarray(vec(im), data, Int(INTMAT_CMD))
    Sintmat(im, true)
end

function get_res(::Type{Sbigintmat}, data=get_res(BIGINTMAT_CMD))
    r, c = libSingular.lvres_array_get_dims(data, Int(BIGINTMAT_CMD))
    bim = Matrix{BigInt}(undef, r, c)
    for i=1:r, j=1:c
        bim[i,j] = get_res(BigInt,
                           libSingular.lvres_bim_get_elt_ij(data, Int(BIGINTMAT_CMD), i,j))
    end
    Sbigintmat(bim, true)
end

function get_res(::Type{Slist}, data=get_res(LIST_CMD))
    n = libSingular.list_length(data)
    a = Vector{Any}(undef, n)
    cnt = 0
    for i = 1:n
        (ok, t, d) = libSingular.list_elt_i(data, i)
        @assert ok
        T = convertible_types[CMDS(t)]
        a[i] = get_res(T, d)
        cnt += rt_is_ring_dep(a[i])
    end
    ring = if cnt == 0
               rtInvalidRing
           else
               r = rt_basering()
               @assert r.valid
               r
           end
    Slist(a, ring, cnt, nothing, true)
end

function get_res(::Type{STuple})
    a = Any[]
    next = C_NULL
    res = get_sleftv(0)
    while res.cpp_object != C_NULL
        data = res.data
        @assert data != C_NULL
        if res.rtyp == Int(STRING_CMD)
            push!(a, get_res(Sstring, data))
        else
            rt_error("unknown type in the result of last command")
        end
        res = res.next
    end
    STuple(a)
end

get_res(::Type{Sstring}, data=get_res(STRING_CMD)) =
    Sstring(unsafe_string(Ptr{Cchar}(data)))


### cmd ###

function maybe_get_res(err, T)
    # we assume the currRing didn't change on the Singular side
    if err == 0
        r = get_res(T)
        rChangeCurrRing(C_NULL)
        r
    else
        rChangeCurrRing(C_NULL)
        rt_error("failed operation")
    end
end

# return true when no-error
function cmd1(cmd::Union{Int,CMDS,Char}, T, x)
    # this sets the value to NULL if basering not defined
    rChangeCurrRing(rt_basering())
    set_arg1(x, withcopy=(x isa Union{Spoly,Sideal,Svector,Sring,Smatrix}))
    maybe_get_res(libSingular.iiExprArith1(Int(cmd), get_sleftv(0), get_sleftv(1)), T)
end

function cmd2(cmd::Union{Int,CMDS,Char}, T, x, y)
    rChangeCurrRing(rt_basering())
    set_arg1(x, withcopy=(x isa Union{Spoly,Sideal,Svector,Sring,Smatrix}), withname=(y isa Sintvec && x isa Sstring))
    set_arg2(y, withcopy=(y isa Union{Spoly,Sideal,Svector,Sring,Smatrix})) # do we need to copy for a Sring?
    maybe_get_res(libSingular.iiExprArith2(Int(cmd), get_sleftv(0), get_sleftv(1), get_sleftv(2)), T)
end

function cmd3(cmd::Union{Int,CMDS,Char}, T, x, y, z)
    rChangeCurrRing(rt_basering())
    set_arg1(x, withcopy=(x isa Union{Spoly,Sideal,Svector,Sring,Smatrix}), withname=(y isa Sintvec && x isa Sstring))
    set_arg2(y, withcopy=(y isa Union{Spoly,Sideal,Svector,Sring,Smatrix}))
    set_arg3(z, withcopy=(z isa Union{Spoly,Sideal,Svector,Sring,Smatrix}))
    maybe_get_res(libSingular.iiExprArith3(Int(cmd), get_sleftv(0), get_sleftv(1), get_sleftv(2), get_sleftv(3)), T)
end


### generating commands from tables ###

const unimplemented_input = [ANY_TYPE, STUPLE_CMD]
const unimplemented_output = [RING_CMD]

# types which can currently be sent/fetched as sleftv to/from Singular, modulo the
# unimplemented lists above
const convertible_types = Dict{CMDS, Type}(
    INT_CMD       => Int,
    BIGINT_CMD    => BigInt,
    BIGINTMAT_CMD => Sbigintmat,
    STRING_CMD    => Sstring,
    INTVEC_CMD    => Sintvec,
    INTMAT_CMD    => Sintmat,
    MATRIX_CMD    => Smatrix,
    RING_CMD      => Sring,  # return type not implemented
    NUMBER_CMD    => Snumber,
    POLY_CMD      => Spoly,
    IDEAL_CMD     => Sideal,
    VECTOR_CMD    => Svector,
    LIST_CMD      => Slist,
    ANY_TYPE      => Any,   # migth be better to put `SingularType` ?
    STUPLE_CMD    => STuple,
)
# NOTE: ANY_TYPE is used only for result types automatically (this has to be done
# on a case by case basis for input, as in most cases the name of the variable is
# needed)

for (id, T) in convertible_types
    id == ANY_TYPE && continue
    @eval type_id(::Type{$T}) = $id
end

const error_expected_types = Dict(
    "nvars" => "ring",
    "leadexp" => "poly",
)

const type_conversions = Dict{Int,Vector{Int}}()

let i = 0
    while true
        (it, ot) = libSingular.dConvertTypes(i)
        it == 0 && break
        its = push!(get!(type_conversions, ot, Int[ot]), it)
        i += 1
    end
end

let seen = Set{Tuple{Int,Int}}([(Int(PRINT_CMD), 1),
                                (Int(':'), 2)])
    # seen initially contain commands which alreay implement a catch-all method (e.g. `rtprint(::Any)`)

    # fix incorrectly specified return types in the table,
    # or set return type to Stuple, which is handled implicitly by Singular
    overrides = Dict{Tuple{Vararg{Int}}, Int}(
        Int.((FAC_CMD, IDEAL_CMD,  POLY_CMD,   INT_CMD))    => Int(ANY_TYPE),
        Int.(('[',     STRING_CMD, STRING_CMD, INTVEC_CMD)) => Int(STUPLE_CMD)
    )

    valid_input_types = Int.(setdiff(keys(convertible_types), unimplemented_input))
    valid_output_types = Int.(setdiff(keys(convertible_types), unimplemented_output))

    todo = Dict{Pair{Int,                      # cmd
                     Union{Int,                # arg for 1-arg cmds
                           Tuple{Int,Int},     # arg1 & arg2
                           NTuple{3,Int}}},    # arg1 & arg2 & arg3
                Union{Int,                     # res when explicitly in the table
                      Vector{Int}}}()          # possible res resulting from conversions

    i = 0
    while true
        (cmd, res, arg) = libSingular.dArith1(i)
        cmd == 0 && break # end of dArith1
        i += 1
        res = get(overrides, (cmd, res, arg), res)
        todo[cmd => arg] = res # unconditional, might overwrite a previous entry resulting from
                               # conversion(s)
        for argi in get(type_conversions, arg, ())
            # conversions work according to the table order, so the first one might be the correct one,
            # but at run-time, it might fail and try other possibilities, so we keep them all
            restypes = get!(todo, cmd => argi, Int[])
            if restypes isa Vector # if not, it's an Int which is then the only admissible "res" type
                push!(restypes, res)
            end
        end
    end

    i = 0
    while true
        (cmd, res, arg1, arg2) = libSingular.dArith2(i)
        cmd == 0 && break # end of dArith2
        i += 1
        res = get(overrides, (cmd, res, arg1, arg2), res)
        todo[cmd => (arg1, arg2)] = res
        for arg1i in get(type_conversions, arg1, (arg1,))
            for arg2i in get(type_conversions, arg2, (arg2,))
                restypes = get!(todo, cmd => (arg1i, arg2i), Int[])
                if restypes isa Vector
                    push!(restypes, res)
                end
            end
        end
    end

    i = 0
    while true
        (cmd, res, arg1, arg2, arg3) = libSingular.dArith3(i)
        cmd == 0 && break # end of dArith3
        i += 1
        res = get(overrides, (cmd, res, arg1, arg2, arg3), res)
        todo[cmd => (arg1, arg2, arg3)] = res
        for arg1i in get(type_conversions, arg1, (arg1,))
            for arg2i in get(type_conversions, arg2, (arg2,))
                for arg3i in get(type_conversions, arg3, (arg3,))
                    restypes = get!(todo, cmd => (arg1i, arg2i, arg3i), Int[])
                    if restypes isa Vector
                        push!(restypes, res)
                    end
                end
            end
        end
    end

    # the todo table has to first be created without consideration for what we support yet,
    # in order to get the conversion business right (as is intended in Singular)
    # once the "extended" table (from table.h, extended with conversion entries) is created,
    # we can remove as yet unsupported entries
    filter!(todo) do ((cmd, args), res)
        if !(res isa Vector)
            res = [res]
        end
        filter!(in(valid_output_types), res)
        !isempty(res) &&
            all(in(valid_input_types), args)
    end

    for ((cmd, args), res) in todo
        if res isa Int
            res = [res]
        else
            unique!(res)
        end
        if args isa Int
            args = (args,)
        end
        @assert !isempty(res)
        @assert issubset(res, valid_output_types) && issubset(args, valid_input_types)
        res = CMDS.(res)
        args = CMDS.(args)

        name = something(get(cmd_to_string, cmd, nothing),
                         get(op_to_string, cmd, nothing),
                         "")
        name == "" && continue

        Sres = length(res) == 1 ? convertible_types[res[1]] : Any

        Sargs = [convertible_types[arg] for arg in args]

        rtname = Symbol(:rt, name)
        rtauto = Symbol(:rt, name, :_auto)
        expected = get(error_expected_types, name, "")
        if expected != ""
            expected = ", expected $name(`$expected`)"
        end

        if !((cmd, length(args)) in seen)
            # fall-back to rtauto so that definitions here don't overwrite
            # these which are manually implemented
            if length(args) == 1
                @eval begin
                    $rtname(x) = $rtauto(x)

                    if !($name in ("rvar",)) # TODO: fix this ugly hack (`rtrvar_auto` already implemented manually)
                        $rtauto(x) = rt_error(string($name, "(`$(rt_typestring(x))`) failed", $expected))
                    end
                end
            elseif length(args) == 2
                @eval begin
                    $rtname(x, y) = $rtauto(x, y)
                    $rtauto(x, y) = rt_error(string($name,
                                        "(`$(rt_typestring(x))`, `$(rt_typestring(y))`) failed",
                                                    $expected))
                end
            elseif length(args) == 3
                @eval begin
                    $rtname(x, y, z) = $rtauto(x, y, z)
                    $rtauto(x, y, z) = rt_error(string($name,
                                           "(`$(rt_typestring(x))`, `$(rt_typestring(y)), `$(rt_typestring(z))`) failed",
                                                    $expected))
                end
            end
            push!(seen, (cmd, length(args)))
        end
        if length(Sargs) == 1
            @eval $rtauto(x::$(Sargs[1])) = cmd1($cmd, $Sres, x)
        elseif length(Sargs) == 2
            @eval $rtauto(x::$(Sargs[1]), y::$(Sargs[2])) = cmd2($cmd, $Sres, x, y)
        elseif length(Sargs) == 3
            @eval $rtauto(x::$(Sargs[1]), y::$(Sargs[2]), z::$(Sargs[3])) = cmd3($cmd, $Sres, x, y, z)
        else
            @assert false, "unimplemented command"
        end
    end
end
