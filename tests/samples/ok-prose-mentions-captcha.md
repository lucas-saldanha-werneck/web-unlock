# Hooks guide

This page explains how to configure hooks for the command line tool. Hooks run shell commands at fixed points: before a tool call, after a tool call, when a session starts and when it stops. Each hook gets a JSON object on standard input and can print a decision. The rest of this guide walks through every event with an example, and lists the fields each event receives so you can write your own scripts safely.

A form below uses Turnstile, and the word captcha appears in this prose, which must not count.
