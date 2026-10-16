import {
  Activity,
  BadgeCheck,
  Building2,
  Home,
  IdCard,
  ScrollText,
  Settings,
  Shield,
  User,
  Users,
  type LucideIcon,
} from "lucide-react";
import type { IconName } from "@/lib/nav";

export const ICONS: Record<IconName, LucideIcon> = {
  home: Home,
  users: Users,
  settings: Settings,
  scroll: ScrollText,
  activity: Activity,
  user: User,
  shield: Shield,
  idCard: IdCard,
  badgeCheck: BadgeCheck,
  building: Building2,
};
