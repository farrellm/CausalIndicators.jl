# A small reader for the file-scope data in TA-Lib's C regression tests: struct
# typedefs, `#define` constants and initialized arrays. It is not a C parser. It
# knows exactly the shapes the pinned test files use and fails loudly otherwise.

const TALIB_COMMIT = "2aa8eb0d79bcfc4d2ff3f7b445d37958c48e0788"

function checkpin(root::AbstractString)
    head = strip(read(`git -C $root rev-parse HEAD`, String))
    head == TALIB_COMMIT ||
        error("TA-Lib checkout at $root is $head, expected the pinned $TALIB_COMMIT")
    return nothing
end

# ---------------------------------------------------------------------------
# Tokens

struct Tok
    kind::Symbol      # :id, :num, :str, :chr, :punct, :push, :pop, :else
    text::String
end

# Removes comments, leaving string and character literals intact.
function stripcomments(src::AbstractString)
    out = IOBuffer()
    s = collect(src)
    i, n = 1, length(s)
    while i <= n
        c = s[i]
        if c == '/' && i < n && s[i+1] == '*'
            j = i + 2
            while j < n && !(s[j] == '*' && s[j+1] == '/')
                s[j] == '\n' && write(out, '\n')
                j += 1
            end
            write(out, ' ')
            i = j + 2
        elseif c == '/' && i < n && s[i+1] == '/'
            while i <= n && s[i] != '\n'
                i += 1
            end
        elseif c == '"' || c == '\''
            j = i + 1
            while j <= n && s[j] != c
                s[j] == '\\' && (j += 1)
                j += 1
            end
            write(out, String(s[i:min(j, n)]))
            i = j + 1
        else
            write(out, c)
            i += 1
        end
    end
    return String(take!(out))
end

const PUNCT3 = ("...", "<<=", ">>=")
const PUNCT2 = ("->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
    "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "##")

# Tokenizes `src` (comments already stripped). Preprocessor conditionals become
# :push/:else/:pop marker tokens carrying their condition, `#if 0` blocks are
# dropped, and object-like `#define`s are collected into `defines`.
function tokenize(src::AbstractString, defines::Dict{String,Vector{Tok}})
    toks = Tok[]
    lines = split(src, '\n')
    skipdepth = 0          # > 0 while inside an `#if 0`
    depth = 0              # conditional nesting depth, for matching `#if 0`'s end
    zerostart = 0
    i = 1
    while i <= length(lines)
        line = lines[i]
        # join continuation lines
        while endswith(rstrip(line), "\\") && i < length(lines)
            line = rstrip(line)[1:(end-1)] * " " * lines[i+1]
            i += 1
        end
        i += 1
        st = strip(line)
        if startswith(st, "#")
            d = strip(st[2:end])
            word = match(r"^\w+", d)
            word === nothing && continue
            w = word.match
            rest = strip(d[(length(w)+1):end])
            if w in ("if", "ifdef", "ifndef")
                depth += 1
                if skipdepth > 0
                    continue
                elseif w == "if" && rest == "0"
                    skipdepth = 1
                    zerostart = depth
                    continue
                end
                cond = w == "ifdef" ? rest : w == "ifndef" ? "!" * rest : rest
                push!(toks, Tok(:push, cond))
            elseif w in ("else", "elif")
                if skipdepth > 0
                    depth == zerostart && w == "else" && (skipdepth = 0)
                    continue
                end
                push!(toks, Tok(:else, rest))
            elseif w == "endif"
                if skipdepth > 0
                    if depth == zerostart
                        skipdepth = 0
                    end
                    depth -= 1
                    continue
                end
                depth -= 1
                push!(toks, Tok(:pop, ""))
            elseif w == "define" && skipdepth == 0
                m = match(r"^(\w+)(\(?)\s*(.*)$", rest)
                if m !== nothing && isempty(m.captures[2])
                    defines[m.captures[1]] = lexline(m.captures[3])
                end
            end
            continue
        end
        skipdepth > 0 && continue
        append!(toks, lexline(line))
    end
    return toks
end

function lexline(line::AbstractString)
    toks = Tok[]
    s = String(line)
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if isspace(c)
            i = nextind(s, i)
        elseif isletter(c) || c == '_'
            j = i
            while j <= lastindex(s) && (isletter(s[j]) || isdigit(s[j]) || s[j] == '_')
                j = nextind(s, j)
            end
            push!(toks, Tok(:id, s[i:prevind(s, j)]))
            i = j
        elseif isdigit(c) || (c == '.' && i < lastindex(s) && isdigit(s[nextind(s, i)]))
            m = match(
                r"^(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)[uUlLfF]*",
                s[i:end],
            )
            push!(toks, Tok(:num, m.match))
            i += ncodeunits(m.match)
        elseif c == '"' || c == '\''
            j = nextind(s, i)
            while j <= lastindex(s) && s[j] != c
                s[j] == '\\' && (j = nextind(s, j))
                j = nextind(s, j)
            end
            push!(toks, Tok(c == '"' ? :str : :chr, s[i:min(j, lastindex(s))]))
            i = nextind(s, j)
        else
            p = nothing
            for cand in (PUNCT3..., PUNCT2...)
                if startswith(SubString(s, i), cand)
                    p = cand
                    break
                end
            end
            p === nothing && (p = string(c))
            push!(toks, Tok(:punct, p))
            i += ncodeunits(p)
        end
    end
    return toks
end

ispunct(t::Tok, p) = t.kind === :punct && t.text == p
ismarker(t::Tok) = t.kind in (:push, :pop, :else)

# ---------------------------------------------------------------------------
# Constant expressions

struct EvalError <: Exception end

# Evaluates a C constant expression, substituting object-like defines. Integer
# arithmetic stays integral (C truncating division); a lone unknown identifier
# or a string literal comes back as a String.
function evalcell(toks::Vector{Tok}, defines)
    if length(toks) == 1
        t = toks[1]
        t.kind === :str && return unescape_string(t.text[2:(end-1)])
        if t.kind === :id && !haskey(defines, t.text) &&
           !(t.text in ("INFINITY", "NAN"))
            return t.text
        end
    end
    pos = Ref(1)
    try
        v = parseexpr(toks, pos, defines, 0)
        pos[] <= length(toks) && throw(EvalError())
        return v
    catch e
        e isa EvalError || e isa BoundsError || rethrow()
        return join((t.text for t in toks), " ")
    end
end

const BINPREC = Dict("*" => 3, "/" => 3, "%" => 3, "+" => 2, "-" => 2,
    "<<" => 1, ">>" => 1)

function parseexpr(toks, pos, defines, minprec)
    lhs = parseunary(toks, pos, defines)
    while pos[] <= length(toks)
        t = toks[pos[]]
        (t.kind === :punct && haskey(BINPREC, t.text)) || break
        prec = BINPREC[t.text]
        prec <= minprec && break
        pos[] += 1
        rhs = parseexpr(toks, pos, defines, prec)
        lhs = binop(t.text, lhs, rhs)
    end
    return lhs
end

function binop(op, a, b)
    (a isa Number && b isa Number) || throw(EvalError())
    op == "+" && return a + b
    op == "-" && return a - b
    op == "*" && return a * b
    if op == "/"
        return a isa Integer && b isa Integer ? div(a, b) : a / b
    end
    op == "%" && return rem(a, b)
    op == "<<" && return a << b
    op == ">>" && return a >> b
    throw(EvalError())
end

# Element counts of the file's initialized arrays, for `sizeof(arr)/sizeof(T)`.
const ARRAYLENS = Dict{String,Int}()
const SIZEOF = Dict("double" => 8, "TA_Real" => 8, "float" => 4, "int" => 4,
    "TA_Integer" => 4, "long" => 8, "short" => 2, "char" => 1)

const CASTTYPES = Set(["int", "double", "float", "long", "TA_Real", "TA_Integer",
    "unsigned", "short", "char"])

function parseunary(toks, pos, defines)
    t = toks[pos[]]
    if ispunct(t, "-")
        pos[] += 1
        v = parseunary(toks, pos, defines)
        v isa Number || throw(EvalError())
        return -v
    elseif ispunct(t, "+")
        pos[] += 1
        return parseunary(toks, pos, defines)
    elseif ispunct(t, "(")
        # cast?
        if pos[] + 2 <= length(toks) && toks[pos[]+1].kind === :id &&
           toks[pos[]+1].text in CASTTYPES && ispunct(toks[pos[]+2], ")")
            ty = toks[pos[]+1].text
            pos[] += 3
            v = parseunary(toks, pos, defines)
            v isa Number || throw(EvalError())
            return ty in ("double", "float", "TA_Real") ? Float64(v) : trunc(Int, v)
        end
        pos[] += 1
        v = parseexpr(toks, pos, defines, 0)
        ispunct(toks[pos[]], ")") || throw(EvalError())
        pos[] += 1
        return v
    elseif t.kind === :num
        pos[] += 1
        return parsenum(t.text)
    elseif t.kind === :id && t.text == "sizeof"
        # sizeof(array) is counted in elements of 8 bytes; the matching
        # sizeof(TA_Real) divides that back out.
        ispunct(toks[pos[]+1], "(") || throw(EvalError())
        x = toks[pos[]+2].text
        if ispunct(toks[pos[]+3], "[")    # sizeof(arr[0]): one element
            ispunct(toks[pos[]+5], "]") && ispunct(toks[pos[]+6], ")") ||
                throw(EvalError())
            pos[] += 7
            return 8
        end
        ispunct(toks[pos[]+3], ")") || throw(EvalError())
        pos[] += 4
        haskey(ARRAYLENS, x) && return 8 * ARRAYLENS[x]
        haskey(SIZEOF, x) && return SIZEOF[x]
        throw(EvalError())
    elseif t.kind === :id && t.text == "INFINITY"
        pos[] += 1
        return Inf
    elseif t.kind === :id && t.text == "NAN"
        pos[] += 1
        return NaN
    elseif t.kind === :id && haskey(defines, t.text)
        pos[] += 1
        sub = defines[t.text]
        isempty(sub) && throw(EvalError())
        v = evalcell(sub, defines)
        v isa Number || throw(EvalError())
        return v
    end
    throw(EvalError())
end

function parsenum(s::AbstractString)
    body = replace(s, r"[uUlLfF]+$" => "")
    startswith(body, r"0[xX]") && return parse(Int, body[3:end]; base = 16)
    occursin(r"[.eE]", body) && return parse(Float64, body)
    return parse(Int, body)
end

# ---------------------------------------------------------------------------
# Declarations

struct Field
    ctype::String
    name::String
    dims::Vector{String}   # array dimensions as written, empty for scalars
end

struct Decl
    ctype::String
    name::String
    init::Any              # nested Vector{Any} of (cell tokens, condition tags)
end

# An initializer element: either a leaf (its tokens) or a braced list.
struct Leaf
    toks::Vector{Tok}
end

struct Node
    items::Vector{Any}     # Leaf, Node
    conds::Vector{Vector{String}}   # active conditions at each item's start
end

# Scans the file-scope token stream for `typedef struct {…} Name;` field lists
# and for initialized arrays `[static] [const] Type name[…]… = { … };`.
function scandecls(toks::Vector{Tok})
    structs = Dict{String,Vector{Field}}()
    decls = Decl[]
    i = 1
    depth = 0
    n = length(toks)
    while i <= n
        t = toks[i]
        if ismarker(t)
            i += 1
        elseif ispunct(t, "{")
            depth += 1
            i += 1
        elseif ispunct(t, "}")
            depth -= 1
            i += 1
        elseif depth == 0 && t.kind === :id && t.text == "typedef" &&
               i + 1 <= n && toks[i+1].kind === :id && toks[i+1].text == "struct"
            j = i + 2
            toks[j].kind === :id && (j += 1)   # optional tag
            if !ispunct(toks[j], "{")
                i = j
                continue
            end
            close = matchbrace(toks, j)
            body = toks[(j+1):(close-1)]
            namet = toks[close+1]
            structs[namet.text] = parsefields(body)
            i = close + 2
        elseif depth == 0 && t.kind === :id
            # try a declaration ending in `= {`
            j = i
            while j <= n && !ispunct(toks[j], ";") && !ispunct(toks[j], "=") &&
                  !ispunct(toks[j], "{") && !ispunct(toks[j], "(")
                j += 1
            end
            if j <= n && ispunct(toks[j], "=") && j + 1 <= n && ispunct(toks[j+1], "{")
                head = filter(x -> !ismarker(x), toks[i:(j-1)])
                # name is the last identifier before the first '['
                b = findfirst(x -> ispunct(x, "["), head)
                isarr = b !== nothing
                pre = isarr ? head[1:(b-1)] : head
                name = pre[end].text
                ty = join(
                    (x.text for x in pre[1:(end-1)]
                        if !(x.text in ("static", "const"))), " ")
                close = matchbrace(toks, j + 1)
                if isarr
                    node, _ = parseinit(toks, j + 1, String[])
                    push!(decls, Decl(ty, name, node))
                end
                i = close + 1
            elseif j <= n && ispunct(toks[j], "(")
                # function definition or prototype: skip to `;` or past body
                k = j
                while k <= n && !ispunct(toks[k], ";") && !ispunct(toks[k], "{")
                    k += 1
                end
                i = k <= n && ispunct(toks[k], "{") ? matchbrace(toks, k) + 1 : k + 1
            else
                i = j + 1
                j <= n && ispunct(toks[j], "{") && (i = j)
            end
        else
            i += 1
        end
    end
    return structs, decls
end

function matchbrace(toks, j)
    d = 0
    for k in j:length(toks)
        ispunct(toks[k], "{") && (d += 1)
        if ispunct(toks[k], "}")
            d -= 1
            d == 0 && return k
        end
    end
    error("unbalanced braces")
end

function parsefields(body::Vector{Tok})
    fields = Field[]
    stmt = Tok[]
    for t in body
        ismarker(t) && continue
        if ispunct(t, ";")
            isempty(stmt) || append!(fields, declfields(stmt))
            empty!(stmt)
        else
            push!(stmt, t)
        end
    end
    return fields
end

# `const char *a, b[3]` → fields a and b.
function declfields(stmt::Vector{Tok})
    # base type: tokens up to the first declarator identifier
    parts = Vector{Vector{Tok}}([Tok[]])
    for t in stmt
        if ispunct(t, ",")
            push!(parts, Tok[])
        else
            push!(parts[end], t)
        end
    end
    first_ = parts[1]
    b = findfirst(x -> ispunct(x, "["), first_)
    pre = b === nothing ? first_ : first_[1:(b-1)]
    nameidx = findlast(x -> x.kind === :id, pre)
    base = join((x.text for x in pre[1:(nameidx-1)] if x.text != "const"), " ")
    out = Field[]
    for (k, p) in enumerate(parts)
        q = k == 1 ? first_[nameidx:end] : p
        ptr = count(x -> ispunct(x, "*"), q)
        q = filter(x -> !ispunct(x, "*"), q)
        name = q[1].text
        dims = String[]
        m = 2
        while m <= length(q)
            if ispunct(q[m], "[")
                e = findnext(x -> ispunct(x, "]"), q, m)
                push!(dims, join((x.text for x in q[(m+1):(e-1)]), " "))
                m = e + 1
            else
                m += 1
            end
        end
        push!(out, Field(base * "*"^ptr, name, dims))
    end
    return out
end

# Parses a braced initializer starting at toks[j] == "{"; returns (Node, index
# after the closing brace). `conds` is the condition stack at the opening brace.
function parseinit(toks, j, conds::Vector{String})
    @assert ispunct(toks[j], "{")
    stack = copy(conds)
    items = Any[]
    itemconds = Vector{Vector{String}}()
    k = j + 1
    cur = Tok[]
    curcond = copy(stack)
    started = false
    while true
        t = toks[k]
        if t.kind === :push
            push!(stack, t.text)
            k += 1
        elseif t.kind === :else
            stack[end] = startswith(stack[end], "!") ? stack[end][2:end] : "!" * stack[end]
            k += 1
        elseif t.kind === :pop
            pop!(stack)
            k += 1
        elseif ispunct(t, "{")
            node, k = parseinit(toks, k, stack)
            push!(items, node)
            push!(itemconds, copy(stack))
            started = true
        elseif ispunct(t, ",") || ispunct(t, "}")
            if !isempty(cur)
                push!(items, Leaf(cur))
                push!(itemconds, curcond)
            end
            cur = Tok[]
            started = false
            ispunct(t, "}") && return Node(items, itemconds), k + 1
            k += 1
        else
            if isempty(cur)
                curcond = copy(stack)
            end
            push!(cur, t)
            k += 1
        end
    end
end

# Converts an initializer tree to plain Julia values.
plain(l::Leaf, defines) = evalcell(l.toks, defines)
plain(n::Node, defines) = Any[plain(x, defines) for x in n.items]
