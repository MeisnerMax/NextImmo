export function Logo({ inverse = false, product = 'Immo' }: { inverse?: boolean; product?: 'Immo' | 'Asset' }) {
  return (
    <span className={`brand ${inverse ? 'brand--inverse' : ''}`} aria-label={`Nex${product}`}>
      <span className="brand__mark" aria-hidden="true">
        NX
      </span>
      <span className="brand__word">
        Nex<span>{product}</span>
      </span>
    </span>
  );
}
