import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { SettingsProvider } from './state/SettingsContext';
import { NowProvider } from './state/NowContext';
import { ToastProvider } from './state/ToastContext';
// Self-hosted variable fonts — bundled + precached so the nightlight type
// renders on a true cold offline launch with zero network calls.
import '@fontsource-variable/fraunces';
import '@fontsource-variable/inter';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <SettingsProvider>
      <NowProvider>
        <ToastProvider>
          <App />
        </ToastProvider>
      </NowProvider>
    </SettingsProvider>
  </StrictMode>,
);
