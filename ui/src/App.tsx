import { A, Route, Router } from "@solidjs/router";

function App() {
  return (
    <Router>
      <Route
        path="/"
        component={() => (
          <>
            <h1>Two</h1>
            <A href="/one">Hi</A>
          </>
        )}
      />
      <Route
        path={"/one"}
        component={() => (
          <>
            {" "}
            <h1>One</h1>
          </>
        )}
      />
    </Router>
  );
}

export default App;
