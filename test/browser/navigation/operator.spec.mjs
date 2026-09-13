import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from '../browser_helpers.mjs';

async function activateButton(page, name) {
  const button = page.getByRole('button', { name, exact: true });
  await expect(button).toBeVisible();
  await expect(button).toBeEnabled();
  await button.click();
}

test('desktop reference rail routes between functional web views', async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);

  await expect(page.getByText('MASTER BUS')).toBeVisible();

  await activateButton(page, 'Patchbay');
  await expect(page.getByText('PATCHBAY', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'CONNECT MIC / USB' })).toBeVisible();

  await activateButton(page, 'Session');
  await expect(page.getByText('SESSION', { exact: true })).toBeVisible();
  await expect(page.getByText('Session tracklist')).toBeVisible();

  await activateButton(page, 'Settings');
  await expect(page.getByText('SETTINGS', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'RE-PROBE CAPABILITIES' })).toBeVisible();

  await activateButton(page, 'Mixer');
  await expect(page.getByText('MASTER BUS')).toBeVisible();
});

test('mixer session actions route directly to the session view', async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);

  await activateButton(page, 'VIEW SESSION');
  await expect(page.getByText('SESSION', { exact: true })).toBeVisible();
  await expect(page.getByText('Session tracklist')).toBeVisible();

  await activateButton(page, 'Mixer');
  await activateButton(page, 'CORRECT');
  await expect(page.getByText('SESSION', { exact: true })).toBeVisible();
  await expect(page.getByText('Session tracklist')).toBeVisible();
});
