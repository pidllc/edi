## Replenishment and Rollouts both for Sams/Walmart
## This is done by Lorraine who figures out either rollout or replnishment.
## folder is Quila/isoft/inbox/walmart

### We do not send out 855 or 856 to Walmart for Rollout and Replenishment. 
### Only 997 is sent out for Rollout and replenishment.

## After invoicing we send 810
1. got to isoft/inbox/walmart on quilla server. Rename the file to date and customer name.
2. EDI -> EDI (850) purchase order -> Walmart - Bulk(Book) Order
3. Get EDI Data & Post to Sales Orders
4. Select the walmart folder from step
5. Select the EDI File to process
6. Say Yes to generating 997 (not for DSV)
7. Generate FA / PO Ack. (997/855)
8. Update excel file with the po information.
9. WinFashion
10. sales order list filter by sales order date. ( use the date range from when the order came in.)
11. Get first and last order number. update the spreadsheet
12. Get total quantitiy and update the spread sheet.
13. Mass update so the WH is showing correctly in winFashion sales order (not for dsv)
    a. Utility -> Mass update -> sales orderheader
    Update WH -> SC (1967522-1967543)
14. Mass update order details (not for dsv)
    a. Utility -> Mass update -> sales orderdetail
    c. Use sql query to filter using the sales order and customer to update the wh again.
    b. update SH -> SC
15. Send out the Acknowledgement (the 997 file generated in step 6)

## Send the details to UNI.
1. Go go sales order.
2. pick one sales order.
3. click on the CustPO# box to open the po detail report
4. filter with first and last number with cancel date and ensure only the pos you want to send details are listed.
5. check box hide price.
6. Print as PDF. Filename as custposummary.pdf
7. go back to sales order tab in winfashion.
8. list all the pos and then export that to excel with headers.
9. Create pivot table.
10. Report -> Sales Order -> backorder detail.
11. sort the batch by cancel date.
12. export that to an excel file with headers
13. click on summary and then export that as pdf.
14. Create a pivot table with information (Uni knows this)
15. Send these details to Lorraine
16. Lorraine verifies the quantitiy.
17. Once you get the cut detail from Lorraine. You need to do mass update for sales order detail to update cut information.
18. Mass update cutnumber click on change and save to save it
19. Send all these documents including cover sheet to karen.
## following steps only apply for replenishment.
20. Karen confirms there are no shortages and we send out pick ticket.
21. for shortages
    A) create pick tickets
    B) do allocation
        a) Utility -> other options -> order ship import/export
        b) customer -> select rpsamsc to and from
        c) createdate (put po date)
        d) order# is sales order range (working on order# 1967522 - 1967543) for po# 3285170098xx
        e) reload
        f) export to any file.
        g) send it to karen to update the quantiticy.
        h) once she sends the excel file back import that file  and click process to update the quantitiy on pick tickets.

# Pick Tickets
1. Sale order
2. List
3. date range for sales order
4. customer name e.g. rps
5. get data
6. Verify quantitiy
7. pick tickets -> multi pick
8. select all and click pick tickets
9. Send it out to Karen 


# Invoicing
## We send #810 for rollout and replenishment when vimi tells us or 4 weeks later.

## Ranji generates invoicing consolidated pallet slips.

## difference between replenishment and rollout is:
1. pick tickets are sent to ranji and telmo
2. Item information is sent out for pallet slips.
3. labels are printed in house for rollouts

## pallet slips rollout only.
1. edi -> logs -> SKU logs
2. Enter first and last po number e.g. (3285170098xx)
3. 3pl needs sku_in column only.



Rajni and telmo do the invoicing.



For burlington. We have two warehouses one in jersey and another in la
NJ goes out to 053 SDQ
LA minimum 512 SDQ

Rules. check the whole file.
1. SDQ 053 or 512 for NJ or LA respectively. SDQ|AS|92|053|84
2. Release order or stand alone order or cancellation. BEG|00|SA|450768801|002|20260617
    a. Release order is revised order or bulk/blanket order
    b. Stand alone
    c. Revised order
    d. BEG would be BEG|01 instead of BEG|00
When there is a revision verify everything and close out the original orders. 

Process is we import the order and send it to sales rep.
They confirm the cut number
The ratio is confirmed by them.
Uni gives the informtation to Vimi for CIT approval.
Vimi has a blanket approval (Do we need to let her know for all or just burlington)
Once this is confirmed we release the orders to 3PL.
Email to 3pl with

 
# GSX folder
1. Go to the folder Quilla\gxs\GXS-in


## EOD
Fedex end of day
Fedex ship manager -> close
End your shipping day
Invoice



## Invoicing
1. pickticket -> list -> todays date range -> customer like dsv
2. verify shipvia Ref is populated for all orders
3. eye ball the number of records.
4. Invoice
5. Multi Invoice Button
6. double click on one invoice to make sure it works and everything looks good.
7. select all and then click the select button and it will invoice.

## ASN
1. EDI -> EDI 856 -> Sams Club DSV
2. customer DSVSAMSC
3. eye ball the number should match invoicing and EOD
4. right click on ck
5. click Generate EDI-856 Button

## Send out DSV Acknowldgement.

1. rename files e.g. date (061826{companycode}) 
2. Open WinFashion
3. go to edi -> EDI (997) FA/(855) POA Multiplefiles





## Delete invoices from the backend 
# select * from invheader WHERE invoiceno >= 9233539 AND invoiceno <= 9233633
# Delete from invheader WHERE invoiceno >= 9233539 AND invoiceno <= 9233633


## Delete carton assignment.
# select * from invdetail Where invoiceno between 9233539 and 9233633

## Open Pick Ticket
# select * from pickheader where pickno between 951474 and 951569
# select * from pickheader where pickno=<pickticket> 951474
# update pckheader set closed='n' where pickno = 951474
# update pckheader set closed='n' where pickno between 951474 and 951569

## reset pick ticket carton assignment