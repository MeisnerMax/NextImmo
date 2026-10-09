import { ImageResponse } from 'next/og';

export const alt = 'NexAsset – Software für Immobilien, Hotels und Teams';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          padding: '70px 78px',
          color: '#fffdf9',
          background:
            'radial-gradient(circle at 86% 18%, rgba(239,123,50,.35), transparent 32%), linear-gradient(135deg, #071c2c, #0d2a3d)',
          fontFamily: 'Arial, sans-serif',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <div
            style={{
              width: 62,
              height: 62,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              border: '1px solid rgba(255,255,255,.28)',
              borderRadius: 16,
              color: '#ef7b32',
              fontSize: 25,
              fontWeight: 800,
            }}
          >
            NX
          </div>
          <div style={{ fontSize: 32, fontWeight: 700 }}>NexAsset</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          <div style={{ maxWidth: 920, fontSize: 67, fontWeight: 750, lineHeight: 1.03 }}>
            Ihr Bestand. Ihr Team. In einer Software.
          </div>
          <div style={{ marginTop: 28, color: '#b8c6cd', fontSize: 27 }}>
            Hausverwaltung · Asset Management · Development · Hotel · KI – 14 Tage kostenlos testen
          </div>
        </div>
      </div>
    ),
    size,
  );
}
