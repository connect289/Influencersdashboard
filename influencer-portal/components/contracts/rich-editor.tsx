"use client";
// The clause and template editor (Tiptap), limited to the contract document model (D-81): paragraphs, headings 2–4,
// bullet and numbered lists, bold, italic and underline. Everything else is switched off, so pasted content outside
// the whitelist is dropped by the editor's schema, and the result is validated again with `richDoc`.
// With `variables`, a picker inserts {{variables}} and {{#if}} blocks (staff only; creators' suggestions are plain).
import { EditorContent, useEditor, useEditorState, type Editor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import {
  Bold,
  Braces,
  Heading2,
  Heading3,
  Italic,
  List,
  ListOrdered,
  Pilcrow,
  Redo2,
  Underline,
  Undo2,
  type LucideIcon,
} from "lucide-react";
import { useTranslations } from "next-intl";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { richDoc, type RichDoc } from "@/lib/contracts/doc";
import { VARIABLES, type VariableDef } from "@/lib/contracts/variables";
import { cn } from "@/lib/utils";

const GROUPS: VariableDef["group"][] = ["creator", "deal", "campaign", "eduwit", "contract"];

function ToolButton({
  icon: Icon,
  label,
  active,
  disabled,
  onClick,
}: {
  icon: LucideIcon;
  label: string;
  active?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      aria-pressed={active}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "inline-flex size-8 items-center justify-center rounded-md text-muted hover:bg-surface-2 hover:text-ink disabled:opacity-40",
        active && "bg-primary-soft text-primary",
      )}
    >
      <Icon className="size-4" aria-hidden />
    </button>
  );
}

function VariableMenu({ editor }: { editor: Editor }) {
  const t = useTranslations();
  const insert = (v: VariableDef) => {
    const text = `{{${v.key}}}`;
    if (v.kind === "table")
      editor
        .chain()
        .focus()
        .insertContent({ type: "paragraph", content: [{ type: "text", text }] })
        .run();
    else editor.chain().focus().insertContent(text).run();
  };
  const condition = (v: VariableDef) => {
    editor
      .chain()
      .focus()
      .insertContent([
        { type: "paragraph", content: [{ type: "text", text: `{{#if ${v.key}}}` }] },
        { type: "paragraph" },
        { type: "paragraph", content: [{ type: "text", text: "{{/if}}" }] },
      ])
      .run();
  };
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className="inline-flex h-8 items-center gap-1 rounded-md px-2 text-sm text-muted hover:bg-surface-2 hover:text-ink"
          >
            <Braces className="size-4" aria-hidden /> {t("contracts.editor.variable")}
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent className="max-h-80 overflow-y-auto">
          {GROUPS.map((g, gi) => (
            <div key={g}>
              {gi > 0 ? <DropdownMenuSeparator /> : null}
              <DropdownMenuLabel>{t(`contracts.editor.groups.${g}`)}</DropdownMenuLabel>
              {VARIABLES.filter((v) => v.group === g && v.kind !== "flag").map((v) => (
                <DropdownMenuItem key={v.key} onSelect={() => insert(v)}>
                  <span className="flex flex-col">
                    <span>{v.label}</span>
                    <code className="text-xs text-muted">{`{{${v.key}}}`}</code>
                  </span>
                </DropdownMenuItem>
              ))}
            </div>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className="inline-flex h-8 items-center gap-1 rounded-md px-2 text-sm text-muted hover:bg-surface-2 hover:text-ink"
          >
            {t("contracts.editor.condition")}
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent className="max-h-80 overflow-y-auto">
          <DropdownMenuLabel>{t("contracts.editor.conditionHint")}</DropdownMenuLabel>
          {VARIABLES.filter((v) => v.kind === "flag").map((v) => (
            <DropdownMenuItem key={v.key} onSelect={() => condition(v)}>
              {v.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}

function Toolbar({ editor, variables }: { editor: Editor; variables: boolean }) {
  const t = useTranslations();
  const s = useEditorState({
    editor,
    selector: ({ editor: e }) => ({
      bold: e.isActive("bold"),
      italic: e.isActive("italic"),
      underline: e.isActive("underline"),
      h2: e.isActive("heading", { level: 2 }),
      h3: e.isActive("heading", { level: 3 }),
      bullet: e.isActive("bulletList"),
      ordered: e.isActive("orderedList"),
      undo: e.can().undo(),
      redo: e.can().redo(),
    }),
  });
  const c = () => editor.chain().focus();
  return (
    <div
      role="toolbar"
      aria-label={t("contracts.editor.toolbar")}
      className="flex flex-wrap items-center gap-0.5 border-b border-line px-1 py-1"
    >
      <ToolButton
        icon={Bold}
        label={t("contracts.editor.bold")}
        active={s.bold}
        onClick={() => c().toggleBold().run()}
      />
      <ToolButton
        icon={Italic}
        label={t("contracts.editor.italic")}
        active={s.italic}
        onClick={() => c().toggleItalic().run()}
      />
      <ToolButton
        icon={Underline}
        label={t("contracts.editor.underline")}
        active={s.underline}
        onClick={() => c().toggleUnderline().run()}
      />
      <span className="mx-1 h-5 w-px bg-line" aria-hidden />
      <ToolButton
        icon={Pilcrow}
        label={t("contracts.editor.paragraph")}
        onClick={() => c().setParagraph().run()}
      />
      <ToolButton
        icon={Heading2}
        label={t("contracts.editor.heading")}
        active={s.h2}
        onClick={() => c().toggleHeading({ level: 2 }).run()}
      />
      <ToolButton
        icon={Heading3}
        label={t("contracts.editor.subheading")}
        active={s.h3}
        onClick={() => c().toggleHeading({ level: 3 }).run()}
      />
      <ToolButton
        icon={List}
        label={t("contracts.editor.bullets")}
        active={s.bullet}
        onClick={() => c().toggleBulletList().run()}
      />
      <ToolButton
        icon={ListOrdered}
        label={t("contracts.editor.numbers")}
        active={s.ordered}
        onClick={() => c().toggleOrderedList().run()}
      />
      <span className="mx-1 h-5 w-px bg-line" aria-hidden />
      <ToolButton
        icon={Undo2}
        label={t("contracts.editor.undo")}
        disabled={!s.undo}
        onClick={() => c().undo().run()}
      />
      <ToolButton
        icon={Redo2}
        label={t("contracts.editor.redo")}
        disabled={!s.redo}
        onClick={() => c().redo().run()}
      />
      {variables ? (
        <>
          <span className="mx-1 h-5 w-px bg-line" aria-hidden />
          <VariableMenu editor={editor} />
        </>
      ) : null}
    </div>
  );
}

export function RichEditor({
  id,
  value,
  onChange,
  variables = false,
  label,
  invalid,
}: {
  id: string;
  value: RichDoc;
  onChange: (doc: RichDoc) => void;
  variables?: boolean;
  label: string;
  invalid?: boolean;
}) {
  const editor = useEditor({
    immediatelyRender: false,
    extensions: [
      StarterKit.configure({
        heading: { levels: [2, 3, 4] },
        blockquote: false,
        code: false,
        codeBlock: false,
        horizontalRule: false,
        strike: false,
        link: false,
      }),
    ],
    content: value,
    editorProps: {
      attributes: {
        id,
        "aria-label": label,
        role: "textbox",
        "aria-multiline": "true",
        class: "px-3 py-2",
      },
    },
    onUpdate: ({ editor: e }) => {
      const parsed = richDoc.safeParse(e.getJSON());
      if (parsed.success) onChange(parsed.data);
    },
  });
  return (
    <div
      className={cn(
        "doc rounded-lg border bg-surface focus-within:border-primary",
        invalid ? "border-danger" : "border-line-strong",
      )}
    >
      {editor ? (
        <Toolbar editor={editor} variables={variables} />
      ) : (
        <div className="h-10 border-b border-line" />
      )}
      <EditorContent editor={editor} />
    </div>
  );
}
