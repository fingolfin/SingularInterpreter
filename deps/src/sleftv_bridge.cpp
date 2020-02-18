#include "jlcxx/jlcxx.hpp"
#include "includes.h"

typedef ssize_t jint; // julia Int

// for calling interpreter routines from SingularInterpreter
static sleftv lvres;

static const char* lv_string_names[3] = {"", "__string_name_1", "__string_name_2"};

static idhdl string_idhdls[3] = {NULL, NULL, NULL};

static idhdl string_idhdl(int i) {
    assert(1 <= i && i <=2);
    idhdl x = string_idhdls[i];
    if (x == NULL) {
        x = IDROOT->set(lv_string_names[i], 0, STRING_CMD, false);
        string_idhdls[i] = x;
    }
    return x;
}

// hack to work around private members from bigintmat
struct bigintmat_twin
{
   coeffs m_coeffs;
   number *v;
   int row;
   int col;
};

static void singular_define_table_h(jlcxx::Module & Singular);

// sleftv simplified, for communication with Julia
struct Sleftv {
   void* lv; // leftv value
   jint typ;
};

struct Dum {
   leftv lv; // leftv value
   jint typ;
};

void init_sleftv(Sleftv _lv, void* data) {
    leftv lv = (leftv)_lv.lv;
    lv->Init();
    lv->data = data;
    lv->rtyp = _lv.typ;
}

namespace jlcxx
{
  template<> struct IsImmutable<Sleftv> : std::true_type {};
  template<> struct IsBits<Sleftv> : std::true_type {};

// template<> struct IsImmutable<Dum> : std::true_type {};
  template<> struct IsBits<sleftv> : std::true_type {};
}

void singular_define_sleftv_bridge(jlcxx::Module & Singular) {

    jlcxx::static_type_mapping<Sleftv>::set_julia_type((jl_datatype_t*)jlcxx::julia_type("Sleftv"));
//    jlcxx::static_type_mapping<sleftv>::set_julia_type((jl_datatype_t*)jlcxx::julia_type("_sleftv"));

//    Singular.method("dumm", [](const Dum& d) { std::cout << d.typ << " --> " << d.lv << " > " << &d <<std::endl; });
    Singular.method("coeffs_BIGINT_fun", []{std::cout << coeffs_BIGINT <<std::endl; return coeffs_BIGINT;});
    // set_sleftv: the Sleftv arg will have its .lv field initialized,
    // and its .typ field must contain the destination type

    Singular.set_const("coeffs_BIGINT", coeffs_BIGINT);

    Singular.method("set_sleftv",
                    [](Sleftv lv, jint x) {
                        assert(lv.typ == INT_CMD);
                        init_sleftv(lv, (void*)x);
                    });

    Singular.method("set_sleftv",
                    [](Sleftv lv, poly x, bool copy) {
                        assert(lv.typ == POLY_CMD || lv.typ == VECTOR_CMD);
                        init_sleftv(lv, copy ? pCopy(x) : x);
                    });

    Singular.method("set_sleftv",
                    [](Sleftv lv, ideal x, bool copy) {
                        assert(lv.typ == IDEAL_CMD);
                        init_sleftv(lv, copy ? idCopy(x) : x);
                    });

    Singular.method("set_sleftv",
                    [](Sleftv lv, matrix x, bool copy) {
                        assert(lv.typ == MATRIX_CMD);
                        init_sleftv(lv, copy ? mp_Copy(x, currRing) : x);
                    });

    Singular.method("set_sleftv",
                    [](Sleftv lv, number x, bool copy) {
                        assert(lv.typ == NUMBER_CMD);
                        init_sleftv(lv, copy ? nCopy(x) : x);
                    });

    Singular.method("set_sleftv_bigint",
                    [](Sleftv lv, void *p) {
                        assert(lv.typ = BIGINT_CMD);
                        auto b = reinterpret_cast<__mpz_struct*>(p) ;
                        number n = n_InitMPZ(b, coeffs_BIGINT);
                        init_sleftv(lv, n);
                    });


    Singular.method("set_sleftv",
                    [](Sleftv lv, ring x, bool copy) {
                        assert(lv.typ = RING_CMD);
                        init_sleftv(lv, (void*)(copy ? rCopy(x) : x));
                    });

    Singular.method("set_sleftv",
                    [](Sleftv lv, const std::string& x, bool withname) {
                        assert(lv.typ = STRING_CMD);
                        // TODO (or not): avoid copying this poor string 2 or 3 times
                        if (withname) {
                            idhdl id = string_idhdl(1); // TODO: fix this 1 !! so that it's not overwritten in the same call
                                                        // (for now only one argument can use this, so it's temporarily safe)
                            IDDATA(id) = omStrDup(x.c_str());
                            lv.typ = IDHDL;
                            init_sleftv(lv, id);
                            leftv(lv.lv)->name = id->id; // Hans says it's necessary to have the name both in the
                                                        // idhdl and as the name field of the sleftv, but they can
                                                        // be the same pointer
                        }
                        else
                            init_sleftv(lv, (void*)(omStrDup(x.c_str())));
                    });

    // for `Vector{Int}`
    Singular.method("set_sleftv",
                    [](Sleftv lv, jlcxx::ArrayRef<ssize_t> a, int d1, int d2) {
                        bool ismatrix = lv.typ == INTMAT_CMD;
                        assert(lv.typ == INTVEC_CMD || ismatrix);
                        assert(d1 * d2 == a.size());
                        assert(ismatrix || d2 == 1);

                        intvec *iv; // cannot use a global intvec, Singular
                                    // then sometimes tries to de-allocate it
                        if (ismatrix) {
                            iv = new intvec(d1, d2, 0);
                            // iv and a use row-major and column-major formats respectively
                            for (int i=0, i2=1; i2<=d2; ++i2)
                                for (int i1=1; i1<=d1; ++i1)
                                    IMATELEM(*iv, i1, i2) = a[i++];
                        }
                        else {
                            iv = new intvec(d1);
                            for (int i=0; i<a.size(); ++i)
                                (*iv)[i] = a[i];
                        }
                        init_sleftv(lv, iv);
                    });

    Singular.method("set_sleftv_bigintmat",
                    [](Sleftv lv, jlcxx::ArrayRef<jl_value_t*> a, int d1, int d2) {
                        assert(lv.typ == BIGINTMAT_CMD);
                        assert(d1 * d2 == a.size());
                        assert(d1 >= 0 && d2 >= 0);

                        auto bim_ = new bigintmat_twin; // we initialize by hand do avoid useless
                                                        // zero-initialization
                        // cf. bigintmat.h
                        bim_ -> m_coeffs = coeffs_BIGINT;
                        bim_ -> row = d1;
                        bim_ -> col = d2;
                        int l = d1 * d2;
                        bim_ -> v = (number *)omAlloc(sizeof(number)*l);
                        auto bim = reinterpret_cast<bigintmat*>(bim_);
                        for (int i = 0, i2=1; i2 <= d2; ++i2)
                            for (int i1=1; i1 <= d1; ++i1) {
                                auto b = reinterpret_cast<__mpz_struct*>(a[i++]);
                                BIMATELEM(*bim, i1, i2) = n_InitMPZ(b, coeffs_BIGINT);
                            }
                        init_sleftv(lv, bim);
                    });

    Singular.method("set_sleftv_list",
                    [](Sleftv lv, jint len) {
                        assert(lv.typ == LIST_CMD);
                        slists* list = (lists)omAllocBin(slists_bin); // segfaults with: `new slists`
                        list->Init(len);
                        init_sleftv(lv, list);
                        return std::make_tuple((void*)list->m, sizeof(sleftv));
                    });

    // TODO: check if lvres must be somehow de-allocated / does not leak
    Singular.method("get_leftv_res",
                    [] {
                        void *res = (void*)lvres.Data();
                        int t = lvres.Typ();
                        bool isnotatuple = lvres.next == NULL;
//                        return std::make_tuple(isnotatuple, Sleftv(res, t));
                        return std::make_tuple(isnotatuple, t, res);

                    });

    Singular.method("get_leftv_res_next",
                    [](void *next) {
                        if (next == NULL) // start the iteration
                            next = &lvres;
                        leftv lvres_next = (leftv)next;
                        return std::make_tuple(lvres_next->Typ(), lvres_next->Data(), (void*)lvres_next->next);
                    });

    Singular.method("lvres_array_get_dims",
                    [] (void* data, int type){
                        jint r, c;
                        intvec *iv;
                        bigintmat *bim;
                        switch (type) {
                        case INTVEC_CMD:
                        case INTMAT_CMD:
                            iv = (intvec*)data;
                            r = iv->rows();
                            c = iv->cols();
                            break;
                        case BIGINTMAT_CMD:
                            bim = (bigintmat*)data;
                            r = bim->rows();
                            c = bim->rows();
                            break;
                        default:
                            assert(false);
                        }
                        return std::make_tuple(r, c);
                    });

    Singular.method("lvres_to_jlarray",
                    [](jlcxx::ArrayRef<ssize_t> a, void* data, int type) {
                        assert(type == INTVEC_CMD || type == INTMAT_CMD);
                        intvec &iv = *(intvec*)data;
                        assert(a.size() == iv.length());
                        int d1 = iv.rows(), d2 = iv.cols();
                        if (type == INTMAT_CMD)
                            for (int i=0, i2=1; i2<=d2; ++i2)
                                for (int i1=1; i1<=d1; ++i1)
                                    a[i++] = IMATELEM(iv, i1, i2);
                        else
                            for (int i=0; i<iv.length(); ++i)
                                a[i] = iv[i];
                    });

    Singular.method("lvres_bim_get_elt_ij",
                    [](void* data, int type, int i, int j) {
                        assert(type == BIGINTMAT_CMD);
                        bigintmat &bim = *(bigintmat*)data;
                        assert(1 <= i && i <= bim.rows() &&
                               1 <= j && j <= bim.cols());
                        return (void*)BIMATELEM(bim, i, j);
                    });

    Singular.method("list_length", [](void* data) {
                                       lists l = (lists)data;
                                       return (jint)(l->nr+1);
                                   });

    Singular.method("list_elt_i",
                    [](void* data, int i) {
                        lists l = (lists)data;
                        assert(0 < i && i <= l->nr+1);
                        sleftv &e = l->m[i-1];
                        void *d;
                        int t;
                        bool ok = true;
                        switch (e.rtyp) {
                        case NUMBER_CMD:
                            d = (void*)nCopy((number)e.data); break;
                        case POLY_CMD:
                            d = (void*)pCopy((poly)e.data); break;
                        case IDEAL_CMD:
                            d = (void*)idCopy((ideal)e.data); break;
                        case INTMAT_CMD:
                            d = (void*)ivCopy((intvec*)e.data); break;
                        case LIST_CMD:
                        case INTVEC_CMD:
                        case INT_CMD:
                        case STRING_CMD: // deep-copied on the julia side
                        case BIGINT_CMD: // deep-copied on the julia side
                            d = (void*)e.data; break;
                        default:
                            d = (void*)NULL;
                            ok = false; // merely returning d=NULL is not enough, some pointer types
                                        // might return 0 as a valid object, e.g. for POLY_CMD it
                                        // means the null polynomial
                        }
                        return std::make_tuple(ok, e.rtyp, d);
                    });

    Singular.method("iiExprArith1",
                    [](int op, void* lv) {
                        int err = iiExprArith1(&lvres, (leftv)lv, op);
                        if (err)
                            errorreported = 0;
                        return err;
                    });

    Singular.method("iiExprArith2",
                    [](int op, void* lv1, void* lv2) {
                        // TODO: check what is the default proccall argument
                        int err = iiExprArith2(&lvres, (leftv)lv1, op, (leftv)lv2);
                        if (err)
                            errorreported = 0;
                        return err;
                    });

    Singular.method("iiExprArith3",
                    [](int op, void* lv1, void* lv2, void* lv3) {
                        int err = iiExprArith3(&lvres, op, (leftv)lv1, (leftv)lv2, (leftv)lv3);
                        if (err)
                            errorreported = 0;
                        return err;
                    });

    Singular.method("rChangeCurrRing", [](ring r) {
                                           ring old = currRing;
                                           rChangeCurrRing(r);
                                           return old;
                                       });

    Singular.method("clear_currRing", [] { rChangeCurrRing(NULL); });

    Singular.method("internal_void_to_ideal_helper",
                      [](void *x) { return reinterpret_cast<ideal>(x); });

    Singular.method("internal_void_to_matrix_helper",
                      [](void *x) { return reinterpret_cast<matrix>(x); });

    Singular.method("internal_void_to_number_helper",
                      [](void *x) { return reinterpret_cast<number>(x); });

    Singular.method("internal_to_void_helper",
                      [](ring x) { return reinterpret_cast<void*>(x); });

    Singular.method("allocate_sleftv_array",
                    [](jlcxx::ArrayRef<void*> a) {
                        int sz = a.size();
                        // TODO: this is leaking memory, but doesn't matter if
                        // allocated only once per session; still decide whether
                        // a static array on the c++ side is better
                        auto slvs = new sleftv[sz];
                        for (int i=0; i<sz; ++i)
                            a[i] = &slvs[i];
                    });

    singular_define_table_h(Singular);
}

// below: only singular_define_table_h stuff

#define IPARITH // necessary in order for table.h to include its content

// macros we here don't care about
#define D(x) NULL

#define ALLOW_LP 0
#define ALLOW_NC 0
#define ALLOW_PLURAL 0
#define ALLOW_RING 0
#define ALLOW_ZZ 0
#define NO_CONVERSION 0
#define NO_NC 0
#define NO_RING 0
#define NO_ZERODIVISOR 0
#define NULL_VAL 0
#define WARN_RING 0

#define jjWRONG NULL
#define jjWRONG2 NULL
#define jjWRONG3 NULL

struct sValCmd1
{
  proc1 p;
  short cmd;
  short res;
  short arg;
  short valid_for;
};

typedef BOOLEAN (*proc2)(leftv,leftv,leftv);

struct sValCmd2
{
  proc2 p;
  short cmd;
  short res;
  short arg1;
  short arg2;
  short valid_for;
};

typedef BOOLEAN (*proc3)(leftv,leftv,leftv,leftv);

struct sValCmd3
{
  proc3 p;
  short cmd;
  short res;
  short arg1;
  short arg2;
  short arg3;
  short valid_for;
};

struct sValCmdM
{
  proc1 p;
  short cmd;
  short res;
  short number_of_args; /* -1: any, -2: any >0, .. */
  short valid_for;
};

typedef void *   (*iiConvertProc)(void * data);
typedef void    (*iiConvertProcL)(leftv out,leftv in);

struct sConvertTypes
{
  int i_typ;
  int o_typ;
  iiConvertProc p;
  iiConvertProcL pl;
};

#include <Singular/table.h>

static void singular_define_table_h(jlcxx::Module & Singular) {
    Singular.method("dArith1",
                    [](int i) {
                        sValCmd1 r = dArith1[i];
                        return std::make_tuple((jint)r.cmd, (jint)r.res, (jint)r.arg);
                    });

    Singular.method("dArith2",
                    [](int i) {
                        sValCmd2 r = dArith2[i];
                        return std::make_tuple((jint)r.cmd, (jint)r.res, (jint)r.arg1, (jint)r.arg2);
                    });

    Singular.method("dArith3",
                    [](int i) {
                        sValCmd3 r = dArith3[i];
                        return std::make_tuple((jint)r.cmd, (jint)r.res,
                                               (jint)r.arg1, (jint)r.arg2, (jint)r.arg3);
                    });

    Singular.method("dConvertTypes",
                    [](int i) {
                        sConvertTypes r = dConvertTypes[i];
                        return std::make_tuple((jint)r.i_typ, (jint)r.o_typ);
                    });
}
