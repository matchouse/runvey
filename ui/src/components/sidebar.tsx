import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import {
  ChevronsUpDown,
  Command,
  EllipsisVertical,
  LayoutDashboard,
  Moon,
  Settings,
  Sun,
  SunMoon,
} from "lucide-react";
import { Badge } from "./ui/badge";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { Avatar, AvatarFallback, AvatarImage } from "./ui/avatar";
import { useTheme } from "@/hooks/theme";

export function AppSidebar() {
  const { setTheme, theme } = useTheme();
  return (
    <Sidebar variant="sidebar">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <SidebarMenuButton
                    className="data-[slot=sidebar-menu-button]:p-1.5!"
                    render={<a href="#" />}
                  />
                }
              >
                <Command className="size-5!" />
                <span className="text-base font-semibold">Acme Inc.</span>
                <Badge variant={"outline"}>Hobby</Badge>
                <ChevronsUpDown className="ml-auto" />
              </DropdownMenuTrigger>
              <DropdownMenuContent className="w-40" align="start">
                <DropdownMenuItem>hi</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton>
                  <LayoutDashboard /> Projects
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <SidebarMenuButton
                    size="lg"
                    className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                  />
                }
              >
                <Avatar className="h-8 w-8">
                  <AvatarImage src={""} alt={"CN"} />
                  <AvatarFallback>CN</AvatarFallback>
                </Avatar>
                <div className="grid flex-1 text-left text-sm leading-tight">
                  <span className="truncate font-medium">Vijay</span>
                  <span className="truncate text-xs text-muted-foreground">
                    vijay@example.com
                  </span>
                </div>
                <EllipsisVertical className="ml-auto size-4" />
              </DropdownMenuTrigger>
              <DropdownMenuContent>
                <DropdownMenuGroup>
                  <DropdownMenuItem className="p-0 font-normal cursor-pointer">
                    <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm w-full">
                      <Avatar className="h-8 w-8">
                        <AvatarImage src={""} alt={"Vijay"} />
                        <AvatarFallback>Vi</AvatarFallback>
                      </Avatar>
                      <div className="grid flex-1 text-left text-sm leading-tight">
                        <span className="truncate font-medium">Vijay</span>
                        <span className="truncate text-xs text-muted-foreground">
                          vijay@example.com
                        </span>
                      </div>
                      <div className="mr-2">
                        <Settings />
                      </div>
                    </div>
                  </DropdownMenuItem>
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
                <DropdownMenuGroup>
                  <DropdownMenuSub>
                    <DropdownMenuSubTrigger>
                      {theme === "light" ? (
                        <Sun />
                      ) : theme === "dark" ? (
                        <Moon />
                      ) : (
                        <SunMoon />
                      )}
                      Theme
                    </DropdownMenuSubTrigger>
                    <DropdownMenuPortal>
                      <DropdownMenuSubContent className={"min-w-34"}>
                        <DropdownMenuCheckboxItem
                          checked={theme === "light"}
                          onCheckedChange={() => setTheme("light")}
                        >
                          Light
                        </DropdownMenuCheckboxItem>
                        <DropdownMenuCheckboxItem
                          checked={theme === "dark"}
                          onCheckedChange={() => setTheme("dark")}
                        >
                          Dark
                        </DropdownMenuCheckboxItem>
                        <DropdownMenuCheckboxItem
                          checked={theme === "system"}
                          onCheckedChange={() => setTheme("system")}
                        >
                          System
                        </DropdownMenuCheckboxItem>
                      </DropdownMenuSubContent>
                    </DropdownMenuPortal>
                  </DropdownMenuSub>
                </DropdownMenuGroup>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
