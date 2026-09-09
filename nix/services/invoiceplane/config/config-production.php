<?php

defined('BASEPATH') || exit('No direct script access allowed');

/*
 * Environment config overrides.  CI_ENV is "production", so CodeIgniter's
 * get_config() (system/core/Common.php) requires this file over
 * application/config/config.php during bootstrap, before CI_Security loads.
 *
 * Why this exists: InvoicePlane 1.7.2.0 validates the CSRF token twice, and
 * the first check destroys what the second one needs.
 * CI_Security::__construct() runs csrf_verify(), which compares the posted
 * token against the ip_csrf_cookie and then unset()s it from $_POST
 * ("we don't want to pollute the _POST array", system/core/Security.php:237).
 * The guard introduced in 1.7.2.0 -- Admin_Controller::ensure_valid_post_request()
 * -> verify_csrf_token() -- then reads that same POST field, finds nothing, logs
 * "CSRF validation failed: Missing or invalid submitted token" and redirects
 * without performing the action.  Deleting an invoice silently did nothing.
 * Upstream: https://github.com/InvoicePlane/InvoicePlane/issues/1694
 *
 * Listing those routes here makes csrf_verify() return at the exclude check,
 * which sits before the unset(), so the token survives for the application's
 * own check.  Protection is preserved, not dropped: verify_csrf_token() does
 * the same hash_equals() double-submit comparison against the same cookie and
 * additionally requires the request to be a POST.
 *
 * Only routes that carry their own check are listed.  Routes that rely solely
 * on the framework check -- invoices/delete_item, quotes/delete_item,
 * clients/delete_client_note, upload/delete_file -- are deliberately absent so
 * they keep it.  Patterns are anchored by CI as '#^<pattern>$#i', so
 * "invoices/delete(/.*)?" cannot match "invoices/delete_item".
 *
 * Drop this file once the upstream fix ships.
 */

$config['csrf_exclude_uris'] = [
    'clients/delete(/.*)?',
    'custom_fields/delete(/.*)?',
    'custom_values/delete(/.*)?',
    'email_templates/delete(/.*)?',
    'families/delete(/.*)?',
    'import/delete(/.*)?',
    'invoice_groups/delete(/.*)?',
    'invoices/delete(/.*)?',
    'invoices/delete_invoice_tax(/.*)?',
    'invoices/recalculate_all_invoices(/.*)?',
    'invoices/recurring/delete(/.*)?',
    'invoices/recurring/stop(/.*)?',
    'payment_methods/delete(/.*)?',
    'payments/delete(/.*)?',
    'products/delete(/.*)?',
    'projects/delete(/.*)?',
    'quotes/delete(/.*)?',
    'quotes/delete_quote_tax(/.*)?',
    'quotes/recalculate_all_quotes(/.*)?',
    'sessions/passwordreset(/.*)?',
    'settings/remove_logo(/.*)?',
    'tasks/delete(/.*)?',
    'tax_rates/delete(/.*)?',
    'units/delete(/.*)?',
    'user_clients/delete(/.*)?',
    'users/delete(/.*)?',
    'users/delete_user_client(/.*)?',
];
