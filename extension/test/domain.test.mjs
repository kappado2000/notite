// node --test extension/test  — potrivirea site-urilor (cine primește parola)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { baseDomain, matches, siteTitle } from '../lib/domain.js';

test('domeniul de bază', () => {
  assert.equal(baseDomain('https://www.emag.ro/login'), 'emag.ro');
  assert.equal(baseDomain('https://login.bt.ro/x'), 'bt.ro');
  assert.equal(baseDomain('emag.ro'), 'emag.ro');
  assert.equal(baseDomain('https://shop.exemplu.com.ro'), 'exemplu.com.ro');
  assert.equal(baseDomain('https://accounts.google.com'), 'google.com');
});

test('parola merge doar spre site-ul ei', () => {
  const emag = { url: 'https://www.emag.ro', title: 'eMAG' };
  assert.ok(matches(emag, 'https://auth.emag.ro/user/login'));
  // site-uri false
  assert.ok(!matches(emag, 'https://emag-login.xyz'));
  assert.ok(!matches(emag, 'https://emag.ro.evil.com/login'));
  assert.ok(!matches(emag, 'https://notemag.ro'));
  // fără adresă: după titlu, exact
  assert.ok(matches({ url: '', title: 'Netflix' }, 'https://www.netflix.com'));
  assert.ok(!matches({ url: '', title: 'Ne' }, 'https://ne.com'));
  assert.ok(!matches({ url: '', title: 'Netflix' }, 'https://netflix-ro.com'));
});

test('titlu', () => {
  assert.equal(siteTitle('https://www.emag.ro/x'), 'Emag');
});
