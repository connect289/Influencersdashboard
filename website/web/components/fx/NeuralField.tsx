import { Atom, BookOpen, BrainCircuit, Cpu, GraduationCap, Lightbulb } from "lucide-react";

/**
 * Decorative neural network behind the hero (D-093): the idea of the product drawn in the background, an AI assistant
 * connecting a student to the right programme. Static SVG from fixed coordinates (no script); signals travel along a
 * few links with CSS and stop for reduced motion and on the low tier. Education and AI glyphs sit at some nodes.
 */
const NODES: [number, number][] = [
  [80, 119],
  [85, 296],
  [64, 548],
  [66, 716],
  [257, 107],
  [278, 354],
  [233, 484],
  [225, 725],
  [396, 108],
  [385, 301],
  [405, 534],
  [373, 742],
  [1017, 128],
  [1050, 370],
  [1047, 487],
  [1046, 744],
  [1185, 106],
  [1174, 295],
  [1195, 497],
  [1178, 723],
  [1329, 169],
  [1327, 363],
  [1339, 551],
  [1372, 693],
];
const LINKS: [number, number][] = [
  [0, 1],
  [0, 4],
  [1, 5],
  [1, 6],
  [2, 3],
  [2, 6],
  [2, 7],
  [3, 7],
  [3, 6],
  [4, 8],
  [4, 9],
  [5, 9],
  [5, 6],
  [6, 10],
  [7, 11],
  [8, 9],
  [8, 5],
  [10, 11],
  [10, 5],
  [11, 6],
  [12, 16],
  [12, 17],
  [12, 13],
  [13, 14],
  [13, 17],
  [13, 18],
  [14, 18],
  [14, 17],
  [15, 19],
  [15, 14],
  [15, 18],
  [16, 20],
  [16, 17],
  [17, 21],
  [18, 22],
  [18, 21],
  [19, 23],
  [19, 18],
  [20, 21],
  [20, 17],
  [21, 22],
  [22, 23],
  [23, 18],
];
const SIGNALS: [number, number][] = [
  [0, 1],
  [2, 3],
  [3, 6],
  [5, 6],
  [8, 5],
  [12, 16],
  [13, 17],
  [15, 19],
  [16, 17],
  [19, 23],
  [21, 22],
];
const HOT = new Set([1, 6, 10, 14, 19, 22]);
const GLYPHS = [
  { Icon: GraduationCap, x: 150, y: 250 },
  { Icon: BookOpen, x: 300, y: 610 },
  { Icon: Lightbulb, x: 70, y: 700 },
  { Icon: BrainCircuit, x: 1280, y: 250 },
  { Icon: Cpu, x: 1130, y: 640 },
  { Icon: Atom, x: 1370, y: 720 },
];

export function NeuralField() {
  return (
    <svg aria-hidden viewBox="0 0 1440 900" preserveAspectRatio="xMidYMid slice" className="neural-field" fill="none">
      {LINKS.map(([a, b]) => (
        <line
          key={`${a}-${b}`}
          className="link"
          x1={NODES[a]![0]}
          y1={NODES[a]![1]}
          x2={NODES[b]![0]}
          y2={NODES[b]![1]}
        />
      ))}
      {SIGNALS.map(([a, b], i) => (
        <line
          key={`s${a}-${b}`}
          className="signal"
          style={{ animationDelay: `${i * 0.9}s` }}
          x1={NODES[a]![0]}
          y1={NODES[a]![1]}
          x2={NODES[b]![0]}
          y2={NODES[b]![1]}
        />
      ))}
      {NODES.map(([x, y], i) => (
        <circle key={i} className={HOT.has(i) ? "node-hot" : "node"} cx={x} cy={y} r={HOT.has(i) ? 5 : 4} />
      ))}
      {GLYPHS.map(({ Icon, x, y }) => (
        <Icon key={`${x}-${y}`} className="glyph" x={x - 22} y={y - 22} width={44} height={44} strokeWidth={1.25} />
      ))}
    </svg>
  );
}
