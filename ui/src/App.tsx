import "./App.css";
import { TooltipProvider } from "@/components/ui/tooltip";
import Layout from "./layouts/app";
import { ThemeProvider } from "@/components/theme-provider";

function App() {
  return (
    <>
      <ThemeProvider>
        <TooltipProvider>
          <Layout>Test</Layout>
        </TooltipProvider>
      </ThemeProvider>
    </>
  );
}

export default App;
