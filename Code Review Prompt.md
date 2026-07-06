# Comprehensive Flutter Code Review Prompt – Van Sales POS Application

You are acting as:

* A Senior Flutter Architect
* A Flutter Performance Expert
* A UX Reviewer
* A POS/ERP Solution Architect
* An FMCG Distribution Domain Expert
* A QA Lead
* A Senior Software Reviewer

Your task is to perform a **complete production-level review** of this Flutter project.

Do not merely identify code issues. Evaluate the project from the perspectives of architecture, business logic, user experience, scalability, maintainability, offline reliability, and long-term support.

Whenever possible, explain **why** something is an issue and recommend the best implementation with sample code.

---

# Project Overview

This application is a **Van Sales POS Application** used by an FMCG distributor in the UAE.

The mobile application acts as an extension of **Zoho Books**.

Each salesman carries a mobile device and performs customer visits throughout the day.

The application must work reliably even in areas with poor or no internet connectivity.

The application synchronizes data with Zoho Books whenever connectivity becomes available.

The application allows salesmen to perform the following operations:

* Customer Orders
* Sales Invoices
* Invoice Collections / Receipts
* Customer Payments
* Expenses
* Sales Returns
* Product Catalogue
* Customer Management
* Stock Management
* Synchronization with Zoho Books

This is a mission-critical business application used throughout the working day.

Reliability and speed are more important than visual effects.

---

# Overall Review Objectives

Determine whether the application is:

* Production ready
* Uniformly implemented
* Easy to maintain
* Responsive
* Fast
* Stable
* Offline capable
* Scalable
* Secure
* Consistent across all modules

Whenever inconsistencies exist, identify them and recommend a standard implementation.

---

# 1. Architecture Review

Evaluate:

* Feature-first architecture
* Clean Architecture
* Separation of Presentation, Domain and Data layers
* Repository pattern
* Service layer
* Dependency Injection
* SOLID principles
* DRY implementation
* Modular design
* Shared components
* Code duplication
* Scalability
* Package organization

Identify architectural weaknesses and recommend improvements.

---

# 2. Uniformity Review

Verify every feature follows the same implementation pattern.

Check consistency of:

* Folder structure
* File naming
* Class naming
* Widget naming
* Bloc/Cubit implementation
* State naming
* Event naming
* API layer
* Repository implementation
* Exception handling
* Logging
* Validation
* Theme usage
* Typography
* Colors
* Padding
* Spacing
* Navigation
* Dialogs
* Snackbars
* Bottom sheets

Highlight every inconsistency.

---

# 3. Business Workflow Review

Review whether the implemented workflows make sense for a real FMCG Van Sales operation.

Review:

Customer Visit

Order Entry

Invoice Generation

Cash Collection

Cheque Collection

Partial Payments

Outstanding Balance

Credit Sales

Cash Sales

Sales Returns

Expense Entry

Day Closing

Synchronization

Stock Updates

Invoice Status

Receipt Allocation

Cancellation

Void Transactions

Draft Transactions

Pending Sync

Conflict Resolution

Determine whether every workflow is complete and robust.

---

# 4. UI State Review

Every screen should correctly support all applicable states.

Review implementation of:

Loading

Empty

Error

Offline

Syncing

Sync Failed

No Internet

Unauthorized

Forbidden

Success

Refreshing

Pagination

Searching

Filtering

No Results

Draft Saved

Submitting

Submitted

Cancelled

Deleted

Retry

Validation Errors

Disabled Controls

Read-only Mode

Skeleton Loading (where appropriate)

Missing state handling should be reported.

---

# 5. Offline-First Review

Since salesmen work in the field, offline capability is critical.

Review:

Offline data storage

Queued transactions

Retry mechanism

Automatic synchronization

Conflict detection

Conflict resolution

Duplicate prevention

Partial synchronization

Resume interrupted sync

Network detection

Local cache

Sync indicators

Pending transaction handling

Data consistency

Recovery after application restart

Ensure no transaction can be lost.

---

# 6. Zoho Books Integration Review

Review integration quality.

Check:

API abstraction

Error handling

Retry logic

Rate limiting

Authentication refresh

Duplicate uploads

Idempotent requests

Sync logging

Failure recovery

Data mapping

Validation before upload

Local-to-remote ID mapping

Status tracking

Background synchronization

---

# 7. Financial Accuracy Review

Review every financial calculation.

Verify:

Totals

Subtotals

Discounts

Line discounts

Invoice discounts

VAT calculations

Rounding

Currency formatting

Receipt allocations

Outstanding balances

Credit limits

Negative values

Refund calculations

Sales return calculations

Expense totals

Floating-point precision issues

No calculation should rely on floating-point arithmetic where exact financial precision is required.

---

# 8. Inventory Review

Review inventory logic.

Verify:

Available stock

Reserved stock

Negative stock prevention

Batch handling (if applicable)

Expiry dates (if applicable)

Free quantities

Bonus items

Stock updates

Returns

Offline stock adjustments

Synchronization consistency

---

# 9. Responsive UI Review

Verify responsiveness for:

Small phones

Large phones

Tablets

Landscape

Desktop

Flutter Web

Check for:

Overflow

Hardcoded dimensions

Fixed fonts

Improper MediaQuery usage

Responsive layouts

Adaptive widgets

Keyboard handling

SafeArea

Orientation changes

Text scaling

---

# 10. Widget Review

Review all widgets.

Determine whether they are:

Reusable

Composable

Small

Maintainable

Const where possible

Stateless where possible

Properly parameterized

Easy to test

Avoiding unnecessary rebuilds

Recommend extraction of duplicated widgets.

---

# 11. Performance Review

Identify:

Expensive rebuilds

Missing const constructors

Heavy widget trees

Inefficient ListViews

Memory leaks

Large object creation

Excessive API calls

Unnecessary Bloc rebuilds

Poor image handling

Poor scrolling performance

Slow startup

---

# 12. UX Review

Review usability.

Check:

Fast data entry

One-handed operation

Minimal typing

Barcode workflow

Search efficiency

Customer selection

Product selection

Confirmation dialogs

Undo support

Loading feedback

Navigation speed

Salesman workflow efficiency

Suggest improvements that reduce taps and increase speed.

---

# 13. Error Handling Review

Review handling of:

API failures

Validation failures

Network failures

Timeouts

Parsing failures

Authentication failures

Permission failures

Unexpected exceptions

Crash prevention

Logging

User-friendly error messages

Recovery options

---

# 14. Security Review

Review:

Authentication

Token storage

Secure storage

Sensitive logging

API keys

Input validation

Authorization

Session expiration

Data protection

---

# 15. Accessibility Review

Review:

Touch target sizes

Contrast

Screen reader support

Semantics

Keyboard navigation

Large text support

---

# 16. Testing Review

Determine whether sufficient tests exist.

Review:

Unit tests

Widget tests

Integration tests

Business logic tests

Offline synchronization tests

Financial calculation tests

Repository tests

Edge cases

---

# 17. Flutter Best Practices

Review usage of:

Material 3

Theme Extensions

Bloc best practices

BuildContext safety

Mounted checks

Extension methods

Localization readiness

Internationalization

Latest Flutter APIs

Proper async handling

---

# 18. Code Quality Review

Review:

Readability

Maintainability

Documentation

Dead code

Unused imports

Magic numbers

Magic strings

Enums

Constants

Lint compliance

Formatting

---

# 19. Suggestions for a Smoother Application

Recommend improvements that would make the application faster and easier to use.

Examples include:

* Faster order entry
* Better customer search
* Smarter product filtering
* Keyboard shortcuts
* Barcode scanning improvements
* Cached lookups
* Faster synchronization
* Better animations where beneficial
* Improved navigation
* Better feedback during long operations
* Reduced user taps
* Optimized list performance
* Better offline indicators
* Improved day-end workflow

Focus on practical enhancements that improve productivity for field sales representatives.

---

# 20. Final Report

Provide:

## Overall Scores (0–10)

* Architecture
* Code Quality
* Maintainability
* UI Consistency
* Responsiveness
* Performance
* Offline Reliability
* Business Workflow Accuracy
* Financial Accuracy
* Security
* Testing
* Production Readiness

## Top 20 Critical Issues

Rank by severity.

## Top 20 Quick Wins

Identify improvements that can be implemented with minimal effort but provide significant value.

## Prioritized Improvement Roadmap

Group recommendations into:

* Critical
* High
* Medium
* Low
* Technical Debt
* Future Enhancements

For every issue found, include:

* File path
* Class
* Method or Widget
* Description
* Business impact
* Technical impact
* Severity (Critical / High / Medium / Low)
* Recommended solution
* Example implementation where appropriate.

Do not limit your review to code quality alone. Evaluate whether this application is suitable for daily use by hundreds of van sales representatives operating in demanding field conditions where reliability, speed, and data integrity are essential.
