// CFPlugIn plumbing for a Spotlight .mdimporter. The work happens in Swift
// (Importer.swift, `VoxLookImportFile`); this file only hands out the interface.
//
// macOS ignores CoreSpotlight's CSImportExtension, so this old API is the only
// way to put .vox metadata into Spotlight.

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <CoreServices/CoreServices.h>

// Must match CFPlugInFactories in project.yml.
#define FACTORY_UUID CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, \
    0x4B, 0x51, 0x9B, 0x9F, 0xBA, 0x7B, 0x44, 0xCE, 0x8A, 0xFE, 0xE0, 0x64, 0xCF, 0x56, 0xF6, 0xB6)

extern Boolean VoxLookImportFile(CFMutableDictionaryRef attributes, CFStringRef path);

typedef struct {
    MDImporterInterfaceStruct *interface;
    CFUUIDRef factoryID;
    UInt32 refCount;
} Importer;

static HRESULT QueryInterface(void *self, REFIID iid, LPVOID *out);
static ULONG AddRef(void *self);
static ULONG Release(void *self);

static Boolean ImportData(void *self, CFMutableDictionaryRef attributes, CFStringRef contentType, CFStringRef path) {
    return VoxLookImportFile(attributes, path);
}

static MDImporterInterfaceStruct interfaceTable = {
    NULL, QueryInterface, AddRef, Release, ImportData,
};

static HRESULT QueryInterface(void *self, REFIID iid, LPVOID *out) {
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    Boolean match = CFEqual(requested, kMDImporterInterfaceID) || CFEqual(requested, IUnknownUUID);
    CFRelease(requested);
    if (!match) {
        *out = NULL;
        return E_NOINTERFACE;
    }
    AddRef(self);
    *out = self;
    return S_OK;
}

static ULONG AddRef(void *self) {
    return ++((Importer *)self)->refCount;
}

static ULONG Release(void *self) {
    Importer *importer = self;
    if (--importer->refCount > 0) return importer->refCount;
    CFPlugInRemoveInstanceForFactory(importer->factoryID);
    CFRelease(importer->factoryID);
    free(importer);
    return 0;
}

// Named in CFPlugInFactories.
void *VoxLookImporterFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    if (!CFEqual(typeID, kMDImporterTypeID)) return NULL;
    Importer *importer = malloc(sizeof(Importer));
    if (!importer) return NULL;
    importer->interface = &interfaceTable;
    importer->factoryID = CFRetain(FACTORY_UUID);
    importer->refCount = 1;
    CFPlugInAddInstanceForFactory(importer->factoryID);
    return importer;
}
