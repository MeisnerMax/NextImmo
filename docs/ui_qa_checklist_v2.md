# UI QA Checklist V2

## 1. Functional Safety
- [ ] Navigation still works for all `GlobalPage` values.
- [ ] Property open/back flow works (`Properties -> Detail -> Back to list`).
- [ ] Scenario switching still flushes pending analysis save.
- [ ] Create/archive property flow unchanged.
- [ ] Search entry points still open and navigate correctly.

## 2. Visual Consistency
- [ ] All migrated screens use V2 tokens.
- [ ] No ad-hoc hard-coded colors in migrated V2 screens.
- [ ] Header/card/table spacing matches spacing scale.
- [ ] Status colors are semantically consistent.

## 3. Accessibility
- [ ] Keyboard tab order is logical in shell and key screens.
- [ ] Focus ring/state visible for buttons, inputs, nav items.
- [ ] Contrast checks meet AA thresholds for text and controls.
- [ ] Dialogs are dismissible via keyboard (Esc where applicable).

## 4. Responsiveness
- [ ] Desktop layout (12-column behavior) renders without clipping.
- [ ] Tablet layout (8-column behavior) stacks and wraps correctly.
- [ ] Mobile/narrow desktop layout (4-column behavior) remains usable.
- [ ] Tables provide horizontal scroll at narrow widths.

## 5. Theme and Density
- [ ] Light theme readability and hierarchy verified.
- [ ] Dark theme readability and hierarchy verified.
- [ ] `comfort`, `compact`, `adaptive` settings apply correctly.
- [ ] Adaptive density changes page padding by viewport width.

## 6. Regression Tests
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Existing engine and offer solver tests remain green.

## 7. Definition of Done
- [ ] Wave scope implemented with no business logic regression.
- [ ] V2 components are used for all migrated surfaces.
- [ ] Accessibility/responsive checks complete.
- [ ] Fallback via feature flags remains available.

