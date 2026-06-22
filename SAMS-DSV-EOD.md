# End of the day EOD

## 3PL will ask to send out EOD and which computer to use for it.

### Step by Step Guide

1.  Go to WinFashion
2.  Go to PickTickets
3.  Click on list
4.  Right Click on Get Data
5.  Select "Pick Date Range" and choose today's date for both to and from
6.  Cust. Like "dsv"
7.  Confirm all records have "Shipvia Ref"
8.  Log into the shipping computer in the warehouse that 3pl said to use.
9.  Go to Fedex Ship Manager.
10. Click on close tab
11. Click on "End your shipping day" button
12. Save the file to the system.
13. Draft an email to send it to the following email addresses.
    - Accounts <accounts@3plwd.com>; Anand Inamdar <anand@pidllc.com>; Karen <karen@3plwd.com>; Myra <Myra@3plwd.com>; Allison Leiva <Allison@3plwd.com>; alicia.edick@fedex.com <alicia.edick@fedex.com>
    - CC: Alyssa <alyssa@pidllc.com>; Sidd Makker <sidd@3plwd.com>; Pidedi <edigroup@pidllc.com>
    - Subject: Samsdvs <date> -- EOD
## That finishes the Fedex Part of the EOD. The next part is invoicing.
1. Go to WinFashion
2. Click Invoice
3. MultiInvoice
4. It should be all the ones that need to be invoiced. If not filter as above pick tickets.
5. Message people that you are invoicing so there is no clash.
6. Wait for the invoicing to finish.

## Once we are done with Invoicing we need to do the ASN (Advanced Ship Notice) and send it out.
1.  Go to WinFashion
2.  Go to EDI menu
3.  Go to "EDI (856) ASN" -> choose "Sams Club DSV"
4.  Change customer to "DSVSAMSC"
5.  Change date to and from both to today.
6.  Right click on ck column
7.  Click Generate EDI-856 button
8.  Click on save.
9.  Append ".out" to the filename
10. Copy the file to iSoft/outbox/walmart 

