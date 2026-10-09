export function Logo({ inverse = false }: { inverse?: boolean }) {
  return (
    <span className={`brand ${inverse ? 'brand--inverse' : ''}`} aria-label="NexAsset">
      <span className="brand__mark" aria-hidden="true">
        NX
      </span>
      <span className="brand__word">
        Nex<span>Asset</span>
      </span>
    </span>
  );
}
