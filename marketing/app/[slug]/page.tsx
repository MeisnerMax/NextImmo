import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { SolutionPage } from '@/components/SolutionPage';
import { absoluteUrl } from '@/lib/seo';
import { solutionBySlug, solutions } from '@/lib/solutions';

export const dynamicParams = false;

export function generateStaticParams() {
  return solutions.map((item) => ({ slug: item.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const s = solutionBySlug(slug);
  if (!s) return {};
  const url = absoluteUrl(`/${s.slug}`);
  return {
    title: { absolute: `${s.title} | NexAsset` },
    description: s.description,
    keywords: s.keywords,
    alternates: { canonical: `/${s.slug}` },
    openGraph: { title: `${s.title} | NexAsset`, description: s.description, url, siteName: 'NexAsset', locale: 'de_DE', type: 'website', images: [{ url: s.shot && !s.shot.phone ? s.shot.src : '/opengraph-image', width: s.shot && !s.shot.phone ? 1600 : 1200, height: s.shot && !s.shot.phone ? 1000 : 630, alt: s.shot?.alt ?? 'NexAsset' }] },
    twitter: { card: 'summary_large_image', title: `${s.title} | NexAsset`, description: s.description },
  };
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const s = solutionBySlug(slug);
  if (!s) notFound();
  return <SolutionPage s={s} />;
}
