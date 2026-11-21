#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <stdarg.h>
#include "dobby.h"
#include "config.h"

// ---------------- logging ----------------
static void s2log(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    @autoreleasepool {
        NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/s2.log"];
        FILE *f = fopen(p.UTF8String, "a");
        if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
        NSLog(@"[s2] %@", s);
    }
}

// ---------------- il2cpp ----------------
typedef void*  (*t_void)(void);
typedef void*  (*t_attach)(void*);
typedef void** (*t_asm)(void*, size_t*);
typedef void*  (*t_asm_img)(void*);
typedef const char* (*t_cstr)(void*);
typedef void*  (*t_cfn)(void*, const char*, const char*);
typedef void*  (*t_mfn)(void*, const char*, int);
typedef void*  (*t_new)(void*);
typedef char*  (*t_str)(const char*);
typedef size_t (*t_ccount)(void*);
typedef void*  (*t_cidx)(void*, size_t);
typedef void*  (*t_methods)(void*, void**);
typedef uint32_t (*t_pcount)(void*);
typedef void*  (*t_param)(void*, uint32_t);
typedef void*  (*t_ptype)(void*);
typedef int    (*t_type)(void*);

static t_void   i_domain_get;
static t_attach i_thread_attach;
static t_asm    i_get_assemblies;
static t_asm_img   i_assembly_image;
static t_cstr   i_image_name;
static t_cfn    i_class_from_name;
static t_mfn    i_method_from_name;
static t_new    i_object_new;
static t_str    i_string_new;
static t_ccount i_class_count;
static t_cidx   i_class_at;
static t_methods i_class_methods;
static t_pcount i_param_count;
static t_param  i_param;
static t_ptype  i_param_type;
static t_type   i_type_of;

static void* g_image;
static bool  g_ready;

#define PTR(m) (*(void**)((uintptr_t)(m)))
#define RESOLVE(var, sym) if (!(var = (void*)dlsym(RTLD_DEFAULT, sym))) return false;

static bool api_ready() {
    return i_domain_get && i_class_from_name && i_class_methods && i_type_of;
}

static bool resolve_api() {
    RESOLVE(i_domain_get,     "il2cpp_domain_get");
    RESOLVE(i_thread_attach,  "il2cpp_thread_attach");
    RESOLVE(i_get_assemblies, "il2cpp_domain_get_assemblies");
    RESOLVE(i_assembly_image, "il2cpp_assembly_get_image");
    RESOLVE(i_image_name,     "il2cpp_image_get_name");
    RESOLVE(i_class_from_name,"il2cpp_class_from_name");
    RESOLVE(i_method_from_name,"il2cpp_class_get_method_from_name");
    RESOLVE(i_object_new,     "il2cpp_object_new");
    RESOLVE(i_string_new,     "il2cpp_string_new");
    RESOLVE(i_class_count,    "il2cpp_image_get_class_count");
    RESOLVE(i_class_at,       "il2cpp_image_get_class");
    RESOLVE(i_class_methods,  "il2cpp_class_get_methods");
    RESOLVE(i_param_count,    "il2cpp_method_get_param_count");
    RESOLVE(i_param,          "il2cpp_method_get_param");
    RESOLVE(i_param_type,     "il2cpp_method_get_param_type");
    RESOLVE(i_type_of,        "il2cpp_type_get_type");
    i_thread_attach(i_domain_get());
    return true;
}

// il2cpp string -> ascii
static void str2c(char *out, size_t n, void *ilstr) {
    out[0] = 0;
    if (!ilstr) return;
    int32_t len = *(int32_t*)((uintptr_t)ilstr + 16);
    const uint16_t *c = (const uint16_t*)((uintptr_t)ilstr + 20);
    size_t j = 0;
    for (int32_t i = 0; i < len && j + 1 < n; i++)
        out[j++] = c[i] < 128 ? (char)c[i] : '?';
    out[j] = 0;
}

static bool contains_any(const char *hay, const char *const *set) {
    if (!hay) return false;
    for (int i = 0; set[i]; i++)
        if (strstr(hay, set[i])) return true;
    return false;
}

static void* resolve_image() {
    size_t n = 0;
    void **asms = i_get_assemblies(i_domain_get(), &n);
    for (size_t i = 0; i < n; i++) {
        void *img = i_assembly_image(asms[i]);
        const char *nm = i_image_name(img);
        if (nm && strstr(nm, "Assembly-CSharp")) return img;
    }
    return NULL;
}

// ---------------- chams ----------------
static void *g_mat;
static void *g_orig[4096];
static void *g_origRend[4096];
static int   g_origN;
static bool  g_chams, g_self;
static bool  g_scanLogged;

static void *new_cham_material() {
    NSString *base = NSBundle.mainBundle.bundlePath;
    NSString *bp = [base stringByAppendingPathComponent:@"Frameworks/chams.bundle"];
    if (![NSFileManager.defaultManager fileExistsAtPath:bp])
        bp = [base stringByAppendingPathComponent:@"chams.bundle"];
    if (![NSFileManager.defaultManager fileExistsAtPath:bp]) {
        s2log(@"chams.bundle NOT FOUND (looked in %@)", base);
        return NULL;
    }
    void *abClass = i_class_from_name(g_image, "UnityEngine", "AssetBundle");
    if (!abClass) return NULL;
    void *loadFile = i_method_from_name(abClass, "LoadFromFile", 1);
    if (!loadFile) return NULL;
    void *ab = ((void*(*)(void*, uint32_t))PTR(loadFile))(i_string_new(bp.UTF8String), 0);
    if (!ab) { s2log(@"bundle load failed"); return NULL; }

    void *loadAsset = i_method_from_name(abClass, "LoadAsset", 1);
    void *shader = ((void*(*)(void*, void*, void*))PTR(loadAsset))(ab, i_string_new("chams"), NULL);
    s2log(@"shader: %p", shader);
    if (!shader) return NULL;

    void *matClass = i_class_from_name(g_image, "UnityEngine", "Material");
    void *mat = i_object_new(matClass);
    void *ctor = i_method_from_name(matClass, "ctor", 1);
    ((void(*)(void*, void*))PTR(ctor))(mat, shader);

    void *setCol = i_method_from_name(matClass, "SetColor", 2);
    if (setCol)
        ((void(*)(void*, void*, float, float, float, float))PTR(setCol))(
            mat, i_string_new("_Color"), CHAM_R, CHAM_G, CHAM_B, CHAM_A);
    return mat;
}

static bool is_player(void *go, bool *self) {
    void *trClass = i_class_from_name(g_image, "UnityEngine", "Transform");
    void *compClass = i_class_from_name(g_image, "UnityEngine", "Component");
    void *objClass = i_class_from_name(g_image, "UnityEngine", "Object");
    void *getTr = i_method_from_name(compClass, "get_transform", 0);
    void *getParent = i_method_from_name(trClass, "get_parent", 0);
    void *getGO = i_method_from_name(compClass, "get_gameObject", 0);
    void *getName = i_method_from_name(objClass, "get_name", 0);
    if (!getTr || !getParent || !getGO || !getName) return false;

    void *tr = ((void*(*)(void*))PTR(getTr))(go);
    char nm[256];
    bool hit = false;
    for (int d = 0; tr && d < 8; d++) {
        void *pgo = ((void*(*)(void*))PTR(getGO))(tr);
        void *ils = ((void*(*)(void*))PTR(getName))(pgo);
        str2c(nm, sizeof nm, ils);
        if (contains_any(nm, kIgnoreMarkers)) return false;
        if (contains_any(nm, kPlayerMarkers)) { hit = true; break; }
        tr = ((void*(*)(void*))PTR(getParent))(tr);
    }
    if (hit && !g_scanLogged) s2log(@"matched chain ending: %s", nm);
    return hit;
}

static void restore_chams() {
    if (!g_origN) return;
    void *rendClass = i_class_from_name(g_image, "UnityEngine", "Renderer");
    void *setMat = i_method_from_name(rendClass, "set_sharedMaterial", 1);
    for (int i = 0; i < g_origN; i++)
        if (g_origRend[i]) ((void(*)(void*, void*))PTR(setMat))(g_origRend[i], g_orig[i]);
    g_origN = 0;
}

static void apply_chams() {
    if (!g_mat) return;
    void *smr = i_class_from_name(g_image, "UnityEngine", "SkinnedMeshRenderer");
    void *obj = i_class_from_name(g_image, "UnityEngine", "Object");
    void *comp = i_class_from_name(g_image, "UnityEngine", "Component");
    void *rend = i_class_from_name(g_image, "UnityEngine", "Renderer");
    void *arr = i_class_from_name(g_image, "System", "Array");
    if (!smr || !obj || !arr) return;

    void *findAll = i_method_from_name(obj, "FindObjectsOfTypeAll", 1);
    void *getLen = i_method_from_name(arr, "get_Length", 0);
    void *getItem = i_method_from_name(arr, "GetValue", 1);
    void *getGO = i_method_from_name(comp, "get_gameObject", 0);
    void *getMat = i_method_from_name(rend, "get_sharedMaterial", 0);
    void *setMat = i_method_from_name(rend, "set_sharedMaterial", 1);
    if (!findAll || !getLen || !getItem || !getGO || !getMat || !setMat) return;

    void *list = ((void*(*)(void*, void*))PTR(findAll))(obj, smr);
    if (!list) return;
    int len = ((int(*)(void*))PTR(getLen))(list);
    if (!g_scanLogged) s2log(@"renderers found: %d", len);

    for (int i = 0; i < len && g_origN < 4096; i++) {
        void *r = ((void*(*)(void*, int))PTR(getItem))(list, i);
        if (!r) continue;
        void *go = ((void*(*)(void*))PTR(getGO))(r);
        if (!go) continue;
        bool self = false;
        if (!is_player(go, &self)) continue;
        if (self && !g_self) continue;
        void *cur = ((void*(*)(void*))PTR(getMat))(r);
        if (cur == g_mat) continue;
        g_origRend[g_origN] = r;
        g_orig[g_origN++] = cur;
        ((void(*)(void*, void*))PTR(setMat))(r, g_mat);
    }
    if (!g_scanLogged && len) { g_scanLogged = true; s2log(@"chams applied: %d", g_origN); }
}

// ---------------- skinchanger ----------------
typedef void (*t_setSkin)(void*, int, void*);
typedef int  (*t_getSkin)(void*, void*);
static t_setSkin orig_setSkin;
static t_getSkin orig_getSkin;
static bool  g_skin;
static int   g_skinId;
static void *g_setHook, *g_getHook;

static void hook_setSkin(void *self, int id, void *m) {
    if (g_skin) id = g_skinId;
    orig_setSkin(self, id, m);
}

static int hook_getSkin(void *self, void *m) {
    int v = orig_getSkin(self, m);
    return g_skin ? g_skinId : v;
}

// walk every class in Assembly-CSharp looking for the configured names
static void find_skin_methods() {
    size_t count = i_class_count(g_image);
    s2log(@"scanning %zu classes", count);
    for (size_t c = 0; c < count; c++) {
        void *klass = i_class_at(g_image, c);
        if (!klass) continue;
        void *it = NULL, *m;
        while ((m = i_class_methods(klass, &it))) {
            const char *name = NULL;
            // il2cpp_method_get_name is stable; resolve once
            static void *(*mname)(void*) = NULL;
            if (!mname) mname = (void*)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");
            if (mname) name = ((const char*(*)(void*))mname)(m);
            if (!name) continue;

            bool isSet = false, isGet = false;
            for (int i = 0; kSkinSetters[i]; i++) if (!strcmp(name, kSkinSetters[i])) isSet = true;
            for (int i = 0; kSkinGetters[i]; i++) if (!strcmp(name, kSkinGetters[i])) isGet = true;
            if (!isSet && !isGet) continue;

            uint32_t pc = i_param_count(m);
            void *mp = PTR(m);
            if (!mp) continue;

            if (isSet && pc == 1) {
                void *pt = i_param(m, 0);
                if (pt && i_type_of(pt) == 0x08) { // IL2CPP_TYPE_I4
                    s2log(@"SET candidate %s.%s @%p", i_image_name(g_image), name, mp);
                    if (!g_setHook) {
                        g_setHook = mp;
                        DobbyHook(mp, (void*)hook_setSkin, (void**)&orig_setSkin);
                        s2log(@"hooked setter");
                    }
                }
            }
            if (isGet && pc == 0) {
                s2log(@"GET candidate %s @%p", name, mp);
                if (!g_getHook) {
                    g_getHook = mp;
                    DobbyHook(mp, (void*)hook_getSkin, (void**)&orig_getSkin);
                    s2log(@"hooked getter");
                }
            }
        }
    }
    if (!g_setHook && !g_getHook) s2log(@"no skin method matched - check config.h");
}

// ---------------- ui ----------------
static UIWindow *g_win;

@interface S2Menu : NSObject
@end

@implementation S2Menu {
    UIButton *_fab; UIView *_panel; UITextField *_tf;
}
- (void)build {
    g_win = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    g_win.windowLevel = 1000000;
    g_win.backgroundColor = UIColor.clearColor;
    g_win.rootViewController = [UIViewController new];
    g_win.hidden = NO;

    _fab = [UIButton buttonWithType:UIButtonTypeSystem];
    _fab.frame = CGRectMake(18, 58, 54, 54);
    _fab.layer.cornerRadius = 27;
    _fab.backgroundColor = [UIColor colorWithRed:.05 green:.05 blue:.07 alpha:.9];
    [_fab setTitle:@"S2" forState:UIControlStateNormal];
    [_fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [g_win addSubview:_fab];

    _panel = [[UIView alloc] initWithFrame:CGRectMake(18, 120, 214, 230)];
    _panel.backgroundColor = [UIColor colorWithRed:.05 green:.05 blue:.07 alpha:.95];
    _panel.layer.cornerRadius = 12;
    _panel.hidden = YES;
    [g_win addSubview:_panel];

    NSArray *titles = @[@"Chams", @"Self chams", @"Skinchanger"];
    CGFloat y = 12;
    for (int i = 0; i < titles.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, y, 110, 31)];
        l.text = titles[i]; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:13];
        UISwitch *s = [UISwitch new];
        s.frame = CGRectMake(132, y, 51, 31); s.tag = i;
        [s addTarget:self action:@selector(sw:) forControlEvents:UIControlEventValueChanged];
        [_panel addSubview:l]; [_panel addSubview:s];
        y += 42;
    }
    _tf = [[UITextField alloc] initWithFrame:CGRectMake(12, y + 4, 190, 34)];
    _tf.placeholder = @"skin id"; _tf.keyboardType = UIKeyboardTypeNumberPad;
    _tf.textColor = UIColor.whiteColor;
    _tf.backgroundColor = [UIColor colorWithWhite:1 alpha:.1];
    _tf.layer.cornerRadius = 6; _tf.textAlignment = NSTextAlignmentCenter;
    [_tf addTarget:self action:@selector(edit:) forControlEvents:UIControlEventEditingChanged];
    [_panel addSubview:_tf];
}
- (void)toggle { _panel.hidden = !_panel.hidden; }
- (void)sw:(UISwitch*)s {
    if (s.tag == 0) { g_chams = s.isOn; if (!s.isOn) restore_chams(); }
    else if (s.tag == 1) g_self = s.isOn;
    else g_skin = s.isOn;
    s2log(@"chams=%d self=%d skin=%d", g_chams, g_self, g_skin);
}
- (void)edit:(UITextField*)t { g_skinId = t.text.intValue; }
@end

static S2Menu *g_menu;

// ---------------- boot ----------------
__attribute__((constructor))
static void boot() {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        s2log(@"--- loaded ---");
        for (int i = 0; i < 600; i++) {
            if (!api_ready() && !resolve_api()) { usleep(100000); continue; }
            g_image = resolve_image();
            if (g_image) break;
            usleep(100000);
        }
        if (!g_image) { s2log(@"Assembly-CSharp not found"); return; }
        s2log(@"image %p", g_image);
        g_ready = true;

        g_mat = new_cham_material();
        s2log(@"material %p", g_mat);

        find_skin_methods();

        dispatch_async(dispatch_get_main_queue(), ^{
            g_menu = [S2Menu new];
            [g_menu build];
        });

        while (true) {
            if (g_chams && g_ready) apply_chams();
            usleep(400000);
        }
    });
}
