"use client";

import { useState } from "react";
import { ArrowRight, Heart, Search, Sparkles } from "lucide-react";
import { Accordion } from "@/components/ui/Accordion";
import { Badge } from "@/components/ui/Badge";
import { BottomSheet } from "@/components/ui/BottomSheet";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { Checkbox } from "@/components/ui/Checkbox";
import { Chip } from "@/components/ui/Chip";
import { CodeInput } from "@/components/ui/CodeInput";
import { EmptyState, FeeBar, GradeMeter, ProgressTrack, Skeleton } from "@/components/ui/DataViz";
import { Field } from "@/components/ui/Field";
import { Input, NativeSelect, Textarea } from "@/components/ui/Input";
import { Odometer } from "@/components/ui/Odometer";
import { Panel } from "@/components/ui/Panel";
import { RangeSlider } from "@/components/ui/RangeSlider";
import { Segmented } from "@/components/ui/Segmented";
import { Tabs } from "@/components/ui/Tabs";
import { Tooltip } from "@/components/ui/Tooltip";
import { formatInrCompact } from "@/lib/format";

function Spec({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="border-border grid gap-4 border-t py-8">
      <h3 className="text-lg font-semibold">{title}</h3>
      <div className="flex flex-wrap items-start gap-4">{children}</div>
    </section>
  );
}

/** Every UI element with its states (spec 10.5). */
export function ComponentGallery() {
  const [code, setCode] = useState("");
  const [fee, setFee] = useState<[number, number]>([80000, 250000]);
  const [seg, setSeg] = useState<"grouped" | "flat">("grouped");
  const [panel, setPanel] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [n, setN] = useState(715);
  const [step, setStep] = useState(2);
  return (
    <div>
      <Spec title="Buttons — variants, sizes, states">
        <Button magnetic>
          Primary <ArrowRight aria-hidden />
        </Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
        <Button variant="glow">
          <Sparkles aria-hidden /> Ask Witty
        </Button>
        <Button variant="link">Link</Button>
        <Button size="sm">Small</Button>
        <Button size="lg">Large</Button>
        <Button size="icon" variant="outline" aria-label="Shortlist">
          <Heart aria-hidden />
        </Button>
        <Button disabled>Disabled</Button>
      </Spec>
      <Spec title="Badges">
        <Badge>Neutral</Badge>
        <Badge tone="verified">UGC-DEB entitled</Badge>
        <Badge tone="amber">Easy EMI available</Badge>
        <Badge tone="info">AICTE</Badge>
        <Badge tone="warning">Check eligibility</Badge>
        <Badge tone="danger">Not eligible</Badge>
      </Spec>
      <Spec title="Chips — default, selected, with count, disabled (zero count), removable">
        <Chip>MBA</Chip>
        <Chip selected count={226}>
          MBA
        </Chip>
        <Chip count={48}>BCA</Chip>
        <Chip count={0} disabled>
          Doctorate
        </Chip>
        <Chip onRemove={() => {}}>Under ₹2 lakh</Chip>
      </Spec>
      <Spec title="Form fields — default, hint, error, disabled, optional">
        <div className="grid w-full max-w-md gap-4">
          <Field label="Full name" hint="As on your marksheet">
            {(p) => <Input id={p.id} aria-describedby={p.describedBy} placeholder="Asha Verma" autoComplete="name" />}
          </Field>
          <Field label="Mobile number" error="Enter a 10-digit Indian mobile number starting with 6–9">
            {(p) => (
              <Input
                id={p.id}
                aria-describedby={p.describedBy}
                aria-invalid={p.invalid}
                inputMode="numeric"
                defaultValue="12345"
              />
            )}
          </Field>
          <Field label="Highest qualification">
            {(p) => (
              <NativeSelect id={p.id} defaultValue="">
                <option value="" disabled>
                  Choose…
                </option>
                <option>Class 12</option>
                <option>Graduation</option>
              </NativeSelect>
            )}
          </Field>
          <Field label="Any questions?" optional>
            {(p) => <Textarea id={p.id} placeholder="Ask anything" />}
          </Field>
          <Field label="Disabled">{(p) => <Input id={p.id} disabled defaultValue="Read only" />}</Field>
          <label className="text-muted flex items-start gap-3 text-sm">
            <Checkbox defaultChecked aria-label="Consent" /> I agree that Eduwit may use my details to help with my
            admission…
          </label>
        </div>
      </Spec>
      <Spec title="Verification code (inline, 6 digits)">
        <CodeInput value={code} onValueChange={setCode} invalid={code.length === 6 && code !== "123456"} />
        <p className="text-subtle text-sm">Try 123456 · wrong code shows the invalid state</p>
      </Spec>
      <Spec title="Fee slider with live histogram · Segmented control">
        <div className="w-full max-w-md">
          <RangeSlider
            min={20000}
            max={450000}
            step={5000}
            value={fee}
            onValueChange={setFee}
            histogram={[2, 5, 9, 14, 11, 8, 6, 5, 3, 2, 1, 1, 0, 1, 0, 1]}
            format={formatInrCompact}
            label="total fee"
          />
        </div>
        <Segmented
          value={seg}
          onValueChange={setSeg}
          label="Results view"
          options={[
            { value: "grouped", label: "Grouped" },
            { value: "flat", label: "All offerings" },
          ]}
        />
      </Spec>
      <Spec title="Surfaces — card with pointer glow and luminous hairline">
        <Card className="w-72 p-5">
          <p className="eyebrow">Postgraduate</p>
          <p className="font-display mt-1 text-xl font-semibold">MBA · Marketing</p>
          <p className="text-muted mt-2 text-sm">Hover to see the pointer-reactive glow (desktop).</p>
        </Card>
        <div className="glass text-muted w-72 rounded-[var(--radius-xl)] p-5 text-sm">
          Glass surface (solid on low tier / no backdrop-filter / high contrast).
        </div>
      </Spec>
      <Spec title="Data as delight — odometer, fee bar, NAAC meter, progress track">
        <div className="grid gap-2">
          <Odometer value={n} className="font-display text-4xl font-semibold" />
          <Button size="sm" variant="outline" onClick={() => setN((v) => v + 37)}>
            Tick +37
          </Button>
        </div>
        <div className="w-64">
          <FeeBar value={120000} min={60000} max={260000} label="Fee position" />
        </div>
        <GradeMeter grade="A+" />
        <GradeMeter grade={null} />
        <div className="w-80">
          <ProgressTrack step={step} total={5} labels={["Contact", "Academics", "Work", "Preferences", "Review"]} />
          <div className="mt-2 flex gap-2">
            <Button size="sm" variant="outline" onClick={() => setStep((s) => Math.max(1, s - 1))}>
              Back
            </Button>
            <Button size="sm" onClick={() => setStep((s) => Math.min(5, s + 1))}>
              Next
            </Button>
          </div>
        </div>
      </Spec>
      <Spec title="Accordion · Tabs · Tooltip">
        <div className="w-full max-w-md">
          <Accordion
            items={[
              { id: "1", title: "What is UGC-DEB?", content: "Explanation…" },
              { id: "2", title: "Is counselling free?", content: "Yes." },
            ]}
          />
        </div>
        <div className="w-full max-w-md">
          <Tabs
            tabs={[
              { value: "fees", label: "Fees", content: "Fee breakdown" },
              { value: "elig", label: "Eligibility", content: "Eligibility" },
              { value: "uni", label: "University", content: "About" },
            ]}
          />
        </div>
        <Tooltip content="UGC-DEB lists the universities allowed to offer online and ODL programmes.">
          <button type="button" className="border-border rounded-full border px-3 py-1.5 text-sm">
            What does UGC-DEB mean?
          </button>
        </Tooltip>
      </Spec>
      <Spec title="Overlays — detail panel (drawer / full-screen sheet) · bottom sheet">
        <Button variant="secondary" onClick={() => setPanel(true)}>
          Open detail panel
        </Button>
        <Button variant="secondary" onClick={() => setSheet(true)}>
          Open bottom sheet
        </Button>
        <Panel
          open={panel}
          onOpenChange={setPanel}
          title="MBA · Marketing"
          description="Example University"
          footer={<Button className="w-full">Apply now</Button>}
        >
          <p className="text-muted">
            Panel content scrolls; header and footer stay put. Escape closes; focus returns to the trigger.
          </p>
        </Panel>
        <BottomSheet
          open={sheet}
          onOpenChange={setSheet}
          title="Filters"
          footer={<Button className="w-full">Show 128 offerings</Button>}
        >
          <p className="text-muted">Drag the handle down to dismiss.</p>
        </BottomSheet>
      </Spec>
      <Spec title="Loading and empty states">
        <div className="grid w-72 gap-2">
          <Skeleton className="h-5 w-2/3" />
          <Skeleton className="h-4" />
          <Skeleton className="h-4 w-5/6" />
        </div>
        <div className="w-full max-w-md">
          <EmptyState
            icon={<Search className="size-5" />}
            title="No exact matches"
            action={<Button variant="secondary">Ask Witty</Button>}
          >
            Try removing “Under ₹50K”, or ask Witty for close alternatives.
          </EmptyState>
        </div>
      </Spec>
    </div>
  );
}
