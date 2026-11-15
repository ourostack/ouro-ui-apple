import ObjectiveC

/// The subclasses of `base` that this image (the app, or the UI test bundle) defines, from the Objective-C runtime: the
/// gallery's pages (`GalleryComponentPage`) and the UI tests' page claims (`GalleryPageClaims`). The runtime filters by
/// image and superclass itself, so no other class is touched. (Walking `objc_copyClassList` from Swift retains every
/// class it reads, and a root class such as `__NSGenericDeallocHandler` crashes the test runner on that retain.)
func subclasses<Base: AnyObject>(of base: Base.Type) -> [Base.Type] {
    objc_enumerateClasses(subclassing: base).compactMap { candidate in
        ObjectIdentifier(candidate) == ObjectIdentifier(base) ? nil : candidate as? Base.Type
    }
}
