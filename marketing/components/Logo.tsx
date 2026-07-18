export function Logo({ inverse = false }: { inverse?: boolean }) {
  return (
    <span className={`brand ${inverse ? 'brand--inverse' : ''}`} aria-label="NextImmo">
      <span className="brand__mark" aria-hidden="true">
        NX
      </span>
      <span className="brand__word">
        Next<span>Immo</span>
      </span>
    </span>
  );
}
